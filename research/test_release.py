"""Offline test of the prototype (release) under LuaJIT: the real game.dll code image (_research/game_25480438.dll,
offsets == RVAs) at a fake base, so signatures and native entry points are checked against the game's own code;
the heap objects (UI manager, offers, the Armory controller with its detail panel and bar) are simulated, and the
native functions are stand-ins acting on that memory (the commit copies the pending loadout like the real one).

Run from the mod folder:  python -B research/test_release.py
"""
import re
import tempfile
from pathlib import Path

from lupa.luajit21 import LuaRuntime

from crack_kit_names import thin

MOD = Path(__file__).resolve().parents[1]
SOURCE = (MOD / 'one_click_armor_set.lua').read_text(encoding='utf-8')
DUMP = MOD.parent / '_research' / 'game_25480438.dll'

HARNESS = r'''
local logdir, image = ...
local real_ffi = require('ffi')
local ffi, bit = real_ffi, require('bit')
BASE = 0x40000000
PROG, MGR, CTL = 0x20000000, 0x22000000, 0x24000000
DETAIL = CTL + 0x119488
BAR, EQUIP = DETAIL + 0x91c0, DETAIL + 0x49f0
fake = {keys = {}, natives = {}}
CowboyBingusModLoader = {api = 1, open_log = function(name)
    if type(name) ~= 'string' or not name:match('^[%w_-]+%.log$') then return nil end
    return io.open(logdir .. '/' .. name, 'w')
end}
local heap, patches = {}, {}
local function le64(v) return ffi.string(ffi.new('uint64_t[1]', v), 8) end
local function le32(v) return ffi.string(ffi.new('uint32_t[1]', v), 4) end
local function f32(v) return ffi.string(ffi.new('float[1]', v), 4) end
local function read_mem(a, n)
    if a >= BASE and a + n <= BASE + #image then
        local s = image:sub(a - BASE + 1, a - BASE + n)
        for _, p in ipairs(patches) do
            local lo, hi = math.max(a, p[1]), math.min(a + n, p[1] + #p[2])
            if lo < hi then s = s:sub(1, lo - a) .. p[2]:sub(lo - p[1] + 1, hi - p[1]) .. s:sub(hi - a + 1) end
        end
        return s
    end
    for k, v in pairs(heap) do
        if k <= a and a + n <= k + #v then return v:sub(a - k + 1, a - k + n) end
    end
end
function fake.put(a, bytes)
    for k, v in pairs(heap) do
        if k <= a and a + #bytes <= k + #v then heap[k] = v:sub(1, a - k) .. bytes .. v:sub(a - k + #bytes + 1); return true end
    end
    return false
end
function fake.put32(a, v) fake.put(a, le32(v)) end
function fake.u32(a) local v = ffi.new('uint32_t[1]'); ffi.copy(v, read_mem(a, 4), 4); return tonumber(v[0]) end
function fake.f32(a) local v = ffi.new('float[1]'); ffi.copy(v, read_mem(a, 4), 4); return tonumber(v[0]) end
function fake.i16(a) local v = ffi.new('int16_t[1]'); ffi.copy(v, read_mem(a, 2), 2); return tonumber(v[0]) end
local function patch(rva, bytes) patches[#patches + 1] = {BASE + rva, bytes} end
local k32 = {
    GetCurrentProcess = function() return nil end,
    GetModuleHandleA = function() return ffi.cast('void *', BASE) end,
    ReadProcessMemory = function(p, addr, buf, size, got)
        fake.reads = (fake.reads or 0) + 1
        local s = read_mem(tonumber(ffi.cast('uint64_t', addr)), tonumber(size))
        if not s then return 0 end
        ffi.copy(buf, s, #s); got[0] = #s; return 1
    end,
    QueryPerformanceFrequency = function(f) f[0] = 10000000; return 1 end,
    QueryPerformanceCounter = function(c) fake.qpc = (fake.qpc or 0) + 37; c[0] = fake.qpc; return 1 end,
    VirtualQuery = function(addr, mbi, len)
        local a = tonumber(ffi.cast('uint64_t', addr))
        if a ~= LOC_FN or not fake.loc_executable then return 0 end
        local m = ffi.cast('uint8_t *', mbi)
        ffi.fill(m, 48)
        ffi.copy(m + 32, le32(0x1000) .. le32(0x20) .. le32(0x1000000), 12)
        return 48
    end,
    WriteProcessMemory = function(p, addr, buf, size, got)
        if not fake.put(tonumber(ffi.cast('uint64_t', addr)), ffi.string(buf, tonumber(size))) then return 0 end
        got[0] = size; return 1
    end,
}
local NATIVE_BY_RVA = {[0x144cfb0] = 'set_visible', [0x143bf90] = 'set_label', [0x143c950] = 'set_string_arg',
                       [0x143a0f0] = 'clear_args', [0x1919250] = 'bar_empty', [0x14476a0] = 'set_position',
                       [0x1447160] = 'set_size', [0x1455a90] = 'commit', [0x1448690] = 'set_color',
                       [0x1327f50] = 'play_sound', [0x18d0210] = 'equip_sound', [0x18d10d0] = 'mark_equipped', [0x191a720] = 'button_state', [0x18d7210] = 'preview_notify', [0x1448ad0] = 'set_opacity', [0x14476a0] = 'set_position', [0xfd97e0] = 'entity_event', [0x1450230] = 'set_image', [0x143eef0] = 'set_uv', [0x1447160] = 'set_size', [0x18d1280] = 'highlight', [0x12f9540] = 'find_mapping', [0xaba910] = 'glyph_texture', [0xae47b0] = 'key_name', [0x144f160] = 'set_anchor', [0x144f0d0] = 'set_pivot', [0x14498c0] = 'set_variable', [0x14491f0] = 'set_layer'}
LOC_FN, LOC_TEXT = 0x26000000, 0x26100000
local function cast(ct, v)
    if ct == 'const char *(*)(uint32_t)' then
        assert(tonumber(ffi.cast('uint64_t', v)) == LOC_FN, 'unexpected localization target')
        return function(key)
            fake.loc_calls = (fake.loc_calls or 0) + 1
            if fake.loc_strings[tonumber(key)] then
                fake.put(LOC_TEXT, fake.loc_strings[tonumber(key)] .. '\0')
                return real_ffi.cast('const char *', LOC_TEXT)
            end
            return nil
        end
    end
    if type(ct) == 'string' and ct:find('%(%*%)') then
        local name = assert(NATIVE_BY_RVA[tonumber(ffi.cast('uint64_t', v)) - BASE], 'unexpected native cast')
        if name == 'find_mapping' then
            return function(input, id, fallback)
                fake.mapping_calls = (fake.mapping_calls or 0) + 1
                fake.mapping_query = string.format('%x %s', tonumber(input), tostring(tonumber(id)))
                if not fake.mapping then return nil end
                fake.mapping_buf = real_ffi.new('uint8_t[20]')
                real_ffi.copy(fake.mapping_buf, fake.mapping, 20)
                return fake.mapping_buf
            end
        elseif name == 'glyph_texture' then
            return function(out, kind, key, extra, variant)
                fake.glyph_query = string.format('%d %d %d', kind, key, extra)
                out[0] = fake.glyph_tex or 0
                return out
            end
        elseif name == 'key_name' then
            return function(kind, key, xbox)
                fake.key_name_buf = real_ffi.new('char[?]', #(fake.key_name or '?') + 1, fake.key_name or '?')
                return fake.key_name_buf
            end
        end
        return function(a, b, c)
            a = tonumber(a)
            local arg = (name == 'set_size' or name == 'set_position' or name == 'set_anchor' or name == 'set_pivot') and string.format('%g,%g', b.x, b.y)
                        or (type(b) == 'number' and tostring(b) or '')
            fake.natives[#fake.natives + 1] = string.format('%s %x %s', name, a - CTL, arg)
            if name == 'set_visible' then
                local f = fake.u32(a); fake.put32(a, b == 1 and bit.bor(f, 0x10) or bit.band(f, bit.bnot(0x10)))
            elseif name == 'set_label' then fake.put32(a + 0x110, tonumber(b))
            elseif name == 'set_string_arg' then fake.text = ffi.string(c)
            elseif name == 'set_size' then fake.put(a + 12, f32(b.x) .. f32(b.y))
            elseif name == 'set_position' then fake.put(a + 4, f32(b.x) .. f32(b.y))
            elseif name == 'set_anchor' then fake.put(a + 0x2c, f32(b.x) .. f32(b.y))
            elseif name == 'set_pivot' then fake.put(a + 0x3c, f32(b.x) .. f32(b.y))
            elseif name == 'bar_empty' then
                for _, o in ipairs({0x378, 0x898}) do fake.put32(a + o, bit.band(fake.u32(a + o), bit.bnot(0x10))) end
            elseif name == 'set_uv' then
                fake.put(a + 0x114, f32(b.x) .. f32(b.y) .. f32(c.x) .. f32(c.y))
                fake.natives[#fake.natives] = string.format('set_uv %x %g,%g %.4f,%g', a - CTL, b.x, b.y, c.x, c.y)
            elseif name == 'preview_kit' then
                fake.put32(a + 0xdc0, tonumber(b))
                fake.natives[#fake.natives] = string.format('preview_kit %x %x', a - CTL, tonumber(b))
            elseif name == 'commit' then fake.put(a + 0x38, read_mem(a + 0x64, 0x2c))
            elseif name == 'set_color' then
                fake.put(a + 0x48, f32(b[0]) .. f32(b[1]) .. f32(b[2]))
                fake.natives[#fake.natives] = string.format('set_color %x %.2f,%.2f,%.2f', a - CTL, b[0], b[1], b[2])
            elseif name == 'play_sound' then fake.natives[#fake.natives] = string.format('play_sound %x', tonumber(b))
            elseif name == 'set_opacity' then
                fake.put(a + 0x44, f32(b))
                fake.natives[#fake.natives] = string.format('set_opacity %x %g', a - CTL, b)
            elseif name == 'entity_event' then
                fake.natives[#fake.natives] = string.format('entity_event %x %x %x', a, tonumber(b), tonumber(c))
            elseif name == 'preview_notify' then
                fake.natives[#fake.natives] = string.format('preview_notify %x (shown %x)', a - CTL, fake.u32(DETAIL + 0xbe00c))
                fake.put32(DETAIL + 0xbe00c, fake.hovered or fake.viewed or 0)  -- the detail panel shows the hovered item
            elseif name == 'highlight' then
                fake.hovered = tonumber(b)
                fake.natives[#fake.natives] = string.format('highlight %x %x', a - CTL, tonumber(b))
                return 1
            elseif name == 'set_layer' then
                fake.put(a + 0xbc, string.char(b % 256, math.floor(b / 256) % 256))
                fake.natives[#fake.natives] = string.format('set_layer %x %d', a - CTL, b)
            elseif name == 'set_variable' then
                fake.natives[#fake.natives] = string.format('set_variable %x %x %g,%g,%g,%g', a - CTL, tonumber(b),
                                                            c[0], c[1], c[2], c[3])
            elseif name == 'set_text' then
                fake.natives[#fake.natives] = string.format('set_text %x %s', a - CTL, ffi.string(b))
            elseif name == 'set_image' then
                fake.put(a + 0x150, ffi.string(ffi.new('uint64_t[1]', c), 8))
                fake.put(a + 0x148, ffi.string(ffi.new('uint64_t[1]', 0x2ba00000000ULL), 8))  -- a material instance
                fake.natives[#fake.natives] = string.format('set_image %x 0x%s 0x%s', a - CTL, bit.tohex(b), bit.tohex(c))
            elseif name == 'equip_sound' or name == 'mark_equipped' or name == 'button_state' then
                fake.natives[#fake.natives] = string.format('%s %x %x', name, a - CTL, tonumber(b))
            end
            return 0
        end
    end
    return real_ffi.cast(ct, v)
end
package.loaded.ffi = setmetatable({load = function() return k32 end, cast = cast}, {__index = real_ffi})
stingray = {
    Keyboard = {button_id = function(n) return n end, pressed = function(id) return fake.keys[id] == true end},
    Mouse = {button_id = function() return 1 end, axis_id = function() return 2 end,
             pressed = function() return fake.click ~= nil end,
             axis = function()
                 local c = fake.click or fake.cursor
                 return c and {x = c[1], y = c[2]} or {x = 0, y = 0}
             end},
}
update = function() end
fake.option_values = {}
ModOptionsMenu = {api = 1, register_option = function(id, spec)
        fake.registered = (fake.registered or '') .. id .. '=' .. spec.label .. ';'; return true end,
    get = function(id) local v = fake.option_values[id]; if v == nil then return true end; return v end}

patch(0x3326e68, le64(MGR)); patch(0x347cef8, le64(PROG))
ROOT = 0x25000000
patch(0x3326308, le64(ROOT))
heap[ROOT] = string.rep('\0', 0x1000)
fake.put(ROOT + 0x10, le64(ROOT + 0x100)); fake.put(ROOT + 0x100 + 0x3e8 - 0x100 + 0x100, le64(LOC_FN))
heap[LOC_TEXT] = string.rep('\0', 0x100)
fake.loc_strings = {}
PLAYERS, COMPONENTS, CM_KEYS, CM_STATES, CM_ENTITIES, ENTITY = 0x27000000, 0x27100000, 0x27200000, 0x27300000, 0x27400000, 0x27500000
patch(0x3326468, le64(PLAYERS)); patch(0x3326a50, le64(COMPONENTS)); patch(0x3483c34, le32(0xffffffff))
for _, a in ipairs({PLAYERS, COMPONENTS, CM_KEYS, CM_STATES, CM_ENTITIES, ENTITY}) do heap[a] = string.rep('\0', 0x200) end
fake.put32(PLAYERS + 0x88, 1); fake.put(PLAYERS + 0xe8, le64(PLAYERS + 0x100)); fake.put32(PLAYERS + 0x108, 7)
fake.put32(COMPONENTS + 0x28, 8); fake.put32(COMPONENTS + 0x2c, 0xffffffff); fake.put32(COMPONENTS + 0x30, 0x9E3779B1)
fake.put(COMPONENTS + 0x20, le64(CM_KEYS)); fake.put(COMPONENTS + 0x50, le64(CM_STATES)); fake.put(COMPONENTS + 0x38, le64(CM_ENTITIES))
for i = 0, 7 do fake.put(CM_KEYS + i * 8, le32(0xffffffff) .. le32(0)) end
local slot = tonumber(ffi.cast('uint32_t', ffi.new('uint64_t', 0x9E3779B1) * 7)) % 8
fake.put(CM_KEYS + slot * 8, le32(7) .. le32(2))
fake.put(CM_ENTITIES + 2 * 8, le64(ENTITY)); fake.put32(ENTITY + 0x10, 0x1234)
fake.put32(CM_STATES + 2 * 36 + 0x20, 5)

heap[PROG] = string.rep('\0', 0xb9ce4 + 24 * 16)
heap[MGR] = string.rep('\0', 0x2000)
heap[CTL] = string.rep('\0', 0x1f9000)
-- Offers {offer id, item id, owned}
function fake.offers(list)
    fake.put32(PROG + 0x1ce0, #list)
    for i, o in ipairs(list) do
        fake.put(PROG + 0xb9ce4 + (i - 1) * 24, le32(i - 1) .. le32(o[1]) .. le32(o[2]))
        fake.put32(PROG + 0x1ce4 + (i - 1) * 184 + 0x14, o[3] and 2 or 1)
        fake.put32(PROG + 0x1ce4 + (i - 1) * 184 + 0x0c, o[4] or 3)
    end
end
-- Widgets: bar 656x60 at local 20,0; its wide children; EQUIP 330x60.
local function widget(a, flags, x, w, h)
    fake.put32(a, flags); fake.put(a + 4, f32(x) .. f32(0) .. f32(w) .. f32(h)); fake.put(a + 84, f32(1))
    fake.put(a + 100, f32(1)); fake.put(a + 140, f32(1)); fake.put(a + 148, f32(1000 + x)); fake.put(a + 156, f32(900))
end
widget(BAR, 0x45011, 20, 656, 60)
for _, o in ipairs({0x220, 0x378, 0x898, 0xdb8, 0xec8, 0xfd8}) do widget(BAR + o, o == 0x220 and 0x45011 or 0x4100b, 0, 656, 60) end
widget(BAR + 0x488, 0x0c1011, 10, 24, 24)
fake.put32(BAR + 0x5e0 + 0x110, 0)
fake.put(BAR + 0x5e0 + 0x48, f32(0.5) .. f32(0.5) .. f32(0.5))
fake.put(BAR + 0x220 + 0x114, f32(0) .. f32(0) .. f32(1) .. f32(1))
fake.put32(EQUIP + 0x47bc, 0xa0a0a0a0); fake.put32(EQUIP + 0x47c0, 0xb0b0b0b0)
widget(EQUIP, 0x45211, 700, 330, 60)
-- The bar's frame (created invisible) and the text's local position.
fake.put(BAR + 0xdb8 + 0x44, f32(0))
widget(BAR + 0x9a8, 0x0c1011, 20, 30, 30)
fake.put(BAR + 0x488 + 4, f32(20) .. f32(0) .. f32(30) .. f32(30))
fake.put(BAR + 0x488 + 0x48, f32(1) .. f32(0.8) .. f32(0)); fake.put(BAR + 0x9a8 + 0x48, f32(0.69) .. f32(0.25) .. f32(0.25))
fake.put(BAR + 0x488 + 0x114, f32(0) .. f32(0) .. f32(1) .. f32(1)); fake.put(BAR + 0x9a8 + 0x114, f32(0) .. f32(0) .. f32(1) .. f32(1))
fake.put32(BAR + 0xb00, 0x1d1013)
fake.put(CTL + 0x7fde8 + 0x92990, le32(0x11111111) .. le32(0x33333333))
fake.put(BAR + 0xec8 + 0x44, f32(1) .. f32(0.27) .. f32(0.27) .. f32(0.27))
fake.put32(BAR + 0x1598, 0x141011); fake.put32(BAR + 0x16b0, 0x1d1011)
fake.put(BAR + 0x5e0 + 4, f32(55) .. f32(0))
-- The price group's icon and text, EQUIP's prompt glyph, the input system.
widget(BAR + 0x1598, 0x141011, 6, 644, 48)
widget(BAR + 0x1968, 0x0c1011, 30, 20, 20); fake.put(BAR + 0x1968 + 0x150, le64(0x1234567890abcdefULL))
widget(BAR + 0x16b0, 0x1d1011, 60, 100, 30)
widget(BAR + 0x2ae0, 0x1d1011, 60, 14, 30); fake.put32(BAR + 0x2ae0 + 0x110, 0x77777777)
widget(BAR + 0x1ac0, 0x0c1011, 90, 20, 20); widget(BAR + 0x2d98, 0x1d1011, 120, 14, 30)
-- The price group's children list (first +0xe0, next +0xe8), in address order.
do
    local kids = {0xec8, 0x1598, 0x16b0, 0x1968, 0x1ac0, 0x2ae0, 0x2d98}
    fake.put(BAR + 0xdb8 + 0xe0, le64(BAR + kids[1]))
    for i = 1, #kids do fake.put(BAR + kids[i] + 0xe8, le64(kids[i + 1] and BAR + kids[i + 1] or 0)) end
end
widget(EQUIP + 0x520 + 0x330, 0x141011, 0, 40, 40)
INPUT = 0x28000000
heap[INPUT] = string.rep('\0', 0xa8000)
BUCKETS = 0x29000000
heap[BUCKETS] = string.rep('\0', 4 * 0x148)
fake.put(INPUT + 0xa7ad0, le64(BUCKETS)); fake.put32(INPUT + 0xa7ad8, 4)
-- The binding's bucket (group 10, action 3) with its mappings (20 bytes each).
function fake.bind(maps)
    fake.put32(BUCKETS + 2 * 0x148, 10 * 65536 + 3); fake.put32(BUCKETS + 2 * 0x148 + 4, #maps)
    for i, m in ipairs(maps) do fake.put(BUCKETS + 2 * 0x148 + 8 + (i - 1) * 20, m) end
end
function fake.map(b0, key) return string.char(b0, 0xff, 0, 0, key % 256, math.floor(key / 256)) .. string.rep(string.char(0), 14) end
patch(0x347cf18, le64(INPUT))
function fake.open_armory()
    fake.put32(MGR + 0x166c, 1); fake.put(MGR + 0x1670, le64(CTL)); fake.put32(MGR + 0x1678, 224)
end
function fake.view(offer) fake.viewed, fake.hovered = offer, nil; fake.put32(DETAIL + 0xbe00c, offer) end
function fake.frames(n) for _ = 1, n do update(0.016) end end
'''

results = []


def check(cond, what):
    results.append(bool(cond))
    print(('PASS ' if cond else 'FAIL ') + what)


def main():
    for pattern in (r'//', r'\bgoto\b', r'&(?!&)', r'~(?!=)', r'<<', r'>>'):
        check(not re.search(pattern, SOURCE.split('\n', 1)[1]), f'no Lua 5.3+ construct {pattern!r}')
    logdir = Path(tempfile.mkdtemp(prefix='esb_proto_'))
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(HARNESS, str(logdir), DUMP.read_bytes())
    body, helmet, cape, card = (thin(n) for n in ('armor_warbond_13_1', 'helmet_warbond_13_1', 'cape_warbond_13_1',
                                                   'banner_warbond_13_1'))
    voidwalker = 0x6478678e
    # Armor and helmet offer ids differ from their item ids; capes and cards use the item id.
    lua.execute('fake.offers({{0x11111111, %d, true}, {0x22222222, %d, true}, {%d, %d, true}, {%d, %d, true}, '
                '{0x33333333, %d, true}})' % (body, helmet, cape, cape, card, card, voidwalker))
    lua.execute(SOURCE)
    f = lua.globals().fake
    log = lambda: (logdir / 'OneClickArmorSet.log').read_text(encoding='utf-8')
    CTL = lua.eval('CTL')
    BAR = lua.eval('BAR') - CTL

    f.frames(5)
    status = (logdir / 'OneClickArmorSet_STATUS.log').read_text(encoding='utf-8')
    check(status.startswith('OK - One Click Armor Set') and 'native functions: OK' in status
          and 'set table: 417 items' + chr(10) in status,
          'globals and native functions verified against the real code:\n' + status)
    check(len(f.natives) == 0, 'nothing touched outside the Armory')

    lua.execute('fake.open_armory(); fake.view(0x33333333)')
    f.frames(5)
    check('Offers read: 5' in log() and len(f.natives) == 0, 'IX-VOIDWALKER (no set): the bar is left alone')

    lua.execute('fake.view(0x11111111); fake.put32(DETAIL + 0x20640 + 0xdc0, %d)' % body)
    f.frames(2)
    calls = list(f.natives.values())
    check(f.text == 'EQUIP RE-2310 HONORARY GUARD SET (4/4)' and 'Bar shown for set RE-2310 Honorary Guard (item %08x: HELMET ARMOR CAPE CARD)' % body in log(),
          'owned warbond armor: EQUIP SET for helmet, armor, cape and card: %r' % f.text)
    check(f.registered == 'alomare.one_click_armor_set.cape=Include Cape;alomare.one_click_armor_set.card=Include Player Card;',
          'cape and card toggles registered in Mod Options Menu: %r' % f.registered)
    check(f.u32(CTL + BAR + 0x378) & 0x10 and f.u32(CTL + BAR + 0x5e0 + 0x110) == 0xc67c7faf,
          'group shown, #COUNT template set')
    want = []
    for i, o in enumerate((0x488, 0x9a8)):
        u0, u1, x, w = ((0, 331 / 344, -7, 331 * 1.02), (12 / 344, 1, 663 - 332 * 1.02, 332 * 1.02))[i]
        want += ['set_image %x 0xf6978e86e4f4b0d5 0x0b6a14c35af5f4e4' % (BAR + o),
                 'set_uv %x %g,0 %.4f,1' % (BAR + o, u0, u1), 'set_size %x %g,72' % (BAR + o, w),
                 'set_position %x %g,0' % (BAR + o, x), 'set_visible %x 1' % (BAR + o),
                 'set_color %x 0.50,0.50,0.50' % (BAR + o)]
    got = [c for c in calls if '%x ' % (BAR + 0x488) in c or '%x ' % (BAR + 0x9a8) in c]
    check(got[:12] == want and f.u32(CTL + BAR + 0x898) & 0x10 and not f.u32(CTL + BAR + 0xb00) & 0x10
          and not any('%x ' % (BAR + 0xdb8) in c or '%x ' % (BAR + 0xec8) in c for c in calls),
          "outline: EQUIP's outline texture in two halves on the icon images, in the text color: %r" % got)
    check(abs(f.f32(CTL + BAR + 0x5e0 + 4) - 27.5) < 0.01, 'text margin halved: %r' % f.f32(CTL + BAR + 0x5e0 + 4))
    # The game resets a piece's crop (its texture loaded) and hides group B (its own bar refresh): both come back.
    lua.execute("local ffi = require('ffi'); local F = function(x) return ffi.string(ffi.new('float[1]', x), 4) end; "
                "fake.put(BAR + 0x9a8 + 0x114, F(0) .. F(0) .. F(1) .. F(1)); "
                "fake.put32(BAR + 0x898, 0x4100b); fake.natives = {}")
    f.frames(10)
    kept = list(f.natives.values())
    check(abs(f.f32(CTL + BAR + 0x9a8 + 0x114) - 12 / 344) < 0.001 and f.u32(CTL + BAR + 0x898) & 0x10
          and ('set_visible %x 1' % (BAR + 0x898)) in kept,
          'outline kept: a reset crop and a re-hidden group are put back the next frame: %r' % kept)
    lua.execute('fake.natives = {}'); f.frames(3)
    check(not any('uv' in c or 'image' in c for c in f.natives.values()), 'nothing re-applied while the outline is intact')
    icons = ('%x ' % (BAR + 0x488), '%x ' % (BAR + 0x9a8))
    check(abs(f.f32(CTL + BAR + 12) - 656) < 0.01
          and not any(('size' in c or 'uv' in c) and not any(k in c for k in icons) for c in calls),
          'the bar keeps its full width: %r' % calls[:3])
    check('engine_root: OK' in status and f.loc_calls is None,
          'set name in English while the localization lookup is not proven executable')
    check(calls.count('bar_empty %x ' % BAR) == 0, 'no restore while showing')


    # Click on the bar (screen rect from +148/+156 and size x scale; fake screen position was set for 656 wide).
    lua.execute('fake.natives = {}; fake.click = {1100, 930}')
    f.frames(1)
    lua.execute('fake.click = nil')
    f.frames(1)
    applied = [f.u32(CTL + 0x38 + o) for o in (0x4, 0x8, 0xc, 0x1c)]
    check(applied == [helmet, cape, body, card] and 'Equipped set RE-2310 Honorary Guard:' in log() and 'NOT APPLIED' not in log(),
          'click equips helmet, cape, body and card through the commit: %r' % list(f.natives.values()))

    calls = list(f.natives.values())
    i = calls.index('commit 0 0') if 'commit 0 0' in calls else -9
    state = 0x27300000 + 2 * 36 + 0x20
    check('Preview fields' not in log(), 'no diagnostic preview logging in the release')
    hov = [c for c in list(f.natives.values()) if c.startswith(('highlight', 'preview_notify'))][-4:]
    f.frames(4)
    hov = [c for c in list(f.natives.values()) if c.startswith(('highlight', 'preview_notify'))][1:5]
    check(hov[:2] == ['highlight 7fde8 33333333', 'preview_notify 7f718 (shown 11111111)']
          and hov[2:4] == ['highlight 7fde8 11111111', 'preview_notify 7f718 (shown 33333333)']
          and f.u32(lua.eval('DETAIL') + 0xbe00c) == 0x11111111 and 'Bar restored' not in log()
          and 'Hover away to 33333333' in log() and 'Hover back to 11111111: ok' in log(),
          'after the equip: a hover away (another set item) and back redresses the model, the bar untouched: %r' % hov)
    check(calls[i - 1] == 'entity_event 1234 bd5b4583 %x' % state and f.u32(state) == 7
          and 'customization event posted' in log(),
          'before the commit: the player\'s customization component bumped (5 -> 7) and its event queued: %r'
          % ((calls[i - 2:i + 1], f.u32(state)),))
    check(calls[i + 1:i + 5] == ['equip_sound 7fde8 11111111', 'mark_equipped 7fde8 11111111',
                                 'button_state %x 6' % (0x119488 + 0x49f0), 'preview_notify 7f718 (shown 0)'],
          'after the commit: the item\'s equip sound and the grid\'s equipped marker: %r' % calls[-4:])
    check('set_color %x 1.00,0.85,0.25' % (BAR + 0x5e0) in calls, 'a click flashes the text yellow')
    f.frames(15)
    lua.execute('fake.natives = {}; fake.cursor = {1100, 930}'); f.frames(2)
    lua.execute('fake.cursor = nil'); f.frames(2)
    calls = list(f.natives.values())
    check(calls[:2] == ['play_sound a0a0a0a0', 'set_color %x 1.00,1.00,1.00' % (BAR + 0x5e0)] and sorted(calls) == sorted(['play_sound a0a0a0a0', 'set_color %x 1.00,1.00,1.00' % (BAR + 0x5e0),
                    'set_color %x 1.00,1.00,1.00' % (BAR + 0x488), 'set_color %x 1.00,1.00,1.00' % (BAR + 0x9a8),
                    'set_color %x 0.50,0.50,0.50' % (BAR + 0x5e0), 'set_color %x 0.50,0.50,0.50' % (BAR + 0x488),
                    'set_color %x 0.50,0.50,0.50' % (BAR + 0x9a8)]),
          'hover: EQUIP\'s hover sound and white text; leaving: its leave sound and the gray back: %r' % calls)
    # Cape and card switched off in Mod Options Menu: only helmet and armor.
    lua.execute("fake.option_values['alomare.one_click_armor_set.cape'] = false; fake.option_values['alomare.one_click_armor_set.card'] = false")
    lua.execute('fake.put(CTL + 0x64, string.rep("\0", 0x2c)); fake.put(CTL + 0x38, string.rep("\0", 0x2c))')
    lua.execute('fake.click = {1100, 930}'); f.frames(1); lua.execute('fake.click = nil'); f.frames(1)
    applied = [f.u32(CTL + 0x38 + o) for o in (0x4, 0x8, 0xc, 0x1c)]
    check(applied == [helmet, 0, body, 0], 'options off: EQUIP SET equips only helmet and armor: %r' % applied)
    check(f.text == 'EQUIP RE-2310 HONORARY GUARD SET (2/2)',
          'options off: the counter leaves the excluded slots out: %r' % f.text)
    lua.execute("fake.option_values = {}")
    f.frames(5)
    # Unapplied native change: skipped.
    lua.execute('fake.put32(CTL + 0x64 + 4, 0x12345678); fake.click = {1100, 930}')
    f.frames(1)
    lua.execute('fake.click = nil; fake.put32(CTL + 0x64 + 4, %d)' % helmet)
    f.frames(1)
    check('Equip skipped: the Armory has an unapplied change' in log(), 'no equip while the Armory has a pending change')

    # Move to the unowned-set case: helmet not owned -> label changes without it.
    lua.execute('fake.natives = {}; fake.view(0x33333333)')
    f.frames(2)
    calls = list(f.natives.values())
    check('Bar restored (no set)' in log() and ('bar_empty %x ' % BAR) in calls
          and abs(f.f32(CTL + BAR + 12) - 656) < 0.01 and abs(f.f32(CTL + BAR + 4) - 20) < 0.01
          and f.u32(CTL + BAR + 0x488) & 0x10 and f.u32(CTL + BAR + 0x5e0 + 0x110) == 0
          and abs(f.f32(CTL + BAR + 0x5e0 + 0x48) - 0.5) < 0.01 and abs(f.f32(CTL + BAR + 0x5e0 + 4) - 55) < 0.01
          and ('set_image %x 0x57fcf14ad069020b 0x30d59fcc1d991407' % (BAR + 0x488)) in calls
          and ('set_image %x 0x57fcf14ad069020b 0x61c5699658bec440' % (BAR + 0x9a8)) in calls
          and abs(f.f32(CTL + BAR + 0x488 + 4) - 20) < 0.01 and abs(f.f32(CTL + BAR + 0x488 + 12) - 30) < 0.01
          and abs(f.f32(CTL + BAR + 0x9a8 + 0x4c) - 0.25) < 0.01 and f.u32(CTL + BAR + 0xb00) & 0x10,
          'moving to an item without a set restores size, position, padlock, label and hides the group')

    lua.execute('fake.offers({{0x11111111, %d, true}, {0x22222222, %d, false}, {%d, %d, false}, {%d, %d, false}, '
                '{0x33333333, %d, true}, {0x44444444, 1, true}})' % (body, helmet, cape, cape, card, card, voidwalker))
    f.frames(125)
    lua.execute('fake.view(0x11111111)')
    f.frames(2)
    check(log().count('Bar shown') == 1, 'armor whose set members are not owned: no bar')

    # The lookup proven executable: the localized name replaces the English one.
    lua.execute("fake.loc_executable = true; fake.loc_strings[0xf3550896] = 'RE-2310 GUARDA DE HONRA'; "
                "fake.loc_strings[0x1b5b48a1] = 'SALDO INSUFICIENTE'")
    lua.execute('fake.offers({{0x11111111, %d, true}, {0x22222222, %d, true}, {%d, %d, true}, {%d, %d, true}, '
                '{0x33333333, %d, true}, {0x44444444, 2, true}, {0x55555555, 3, true}})'
                % (body, helmet, cape, cape, card, card, voidwalker))
    f.frames(125)
    lua.execute('fake.view(0x33333333)'); f.frames(2)
    lua.execute('fake.natives = {}; fake.view(%d)' % card); f.frames(2)
    check(f.text == 'EQUIPAR CONJUNTO RE-2310 GUARDA DE HONRA (4/4)' and 'Language: bp' in log(),
          'language recognized, localized set name and label: %r' % f.text)
    lua.execute("fake.loc_strings[0x1b5b48a1] = 'LOW FUNDS'; fake.loc_strings[0xf3550896] = 'RE-2310 HONORARY GUARD'; "
                "fake.put32(MGR + 0x166c, 0)")
    f.frames(2)
    lua.execute('fake.open_armory()'); f.frames(3)
    check(f.text == 'EQUIP RE-2310 HONORARY GUARD SET (4/4)' and 'Language: en' in log(),
          'language switched in the options: detected again when the Armory reopens: %r' % f.text)
    lua.execute('fake.put(CTL + 0x64, read_mem and "" or ""); fake.click = {1100, 930}')
    lua.execute('fake.put(CTL + 0x38, string.rep("\\0", 0x2c)); fake.put(CTL + 0x64, string.rep("\\0", 0x2c))')
    lua.execute('fake.natives = {}; fake.click = {1100, 930}'); f.frames(1); lua.execute('fake.click = nil'); f.frames(1)
    calls = list(f.natives.values())
    check('play_sound 80680c11' in calls and not any(c.startswith('equip_sound') for c in calls)
          and any(c.startswith('entity_event') for c in calls),
          'equipping from a player card plays the card equip sound: %r' % calls[:6])
    f.frames(600)
    version = re.search(r"local M = \{version = '([^']+)'", SOURCE).group(1)
    revision = '-' in version  # test builds (2-revision-K) may log their cost; a release must not
    check(revision or 'Cost in the Armory' not in log(), 'no cost logging in a release (%s)' % version)
    # Keybind: Mod Bindings Menu registration, the assigned action, the glyph, a press equips.
    (logdir / 'ModBindingsMenu.assignments').write_text(
        'alomare.one_click_armor_set.equip_set' + chr(9) + '10' + chr(9) + '3' + chr(10) + 'other' + chr(9) + '9'
        + chr(9) + '1' + chr(10))
    lua.execute('''CowboyBingusModLoader.log_directory = %r
        fake.down = false
        ModBindingsMenu = {api = 1, register_binding = function(id, label, slot, opts)
            fake.binding = string.format('%%s|%%s|%%s|%%s', id, label, tostring(slot), opts and opts.category or '')
            return true end,
            is_down = function(id) return fake.down end}''' % str(logdir).replace(chr(92), '/'))
    lua.execute('fake.view(0x33333333)'); f.frames(12)
    check(f.binding == 'alomare.one_click_armor_set.equip_set|Equip Set|nil|One Click Armor Set',
          'binding registered without a slot under the mod category: %r' % f.binding)
    # A key: keyboard mapping (kind 4, device 3), no glyph texture -> keycap with the key's name.
    # EQUIP's mapping says the mouse is in use; the binding has a keyboard key (F) and a pad button (Xbox X).
    lua.execute('fake.mapping = fake.map(0x44, 0x20); fake.bind({fake.map(0x43, 0x46), fake.map(0x42, 0x12)})'
                '; fake.key_name = "F"; fake.glyph_tex = nil; fake.natives = {}')
    lua.execute('fake.view(0x11111111)'); f.frames(40)
    nat = list(f.natives.values())
    price = [n for n in nat if '123fb0' in n or '125128' in n or '122c28' in n]
    check('Binding action: group 10, action 3' in log() and f.mapping_query == '28000000 42949672960'
          and 'Glyph: key F (device 3, kind 4, key 70)' in log(),
          'the device in use comes from EQUIP (0/10), the binding mappings from its bucket: %r' % f.mapping_query)
    check('set_image 123fb0 0xc0f3797849262087 0x60116f30f97f2f5a' in nat and 'set_string_arg 125128 2871687989' in nat
          and 'Glyph: key F' in log() and f.glyph_query == '4 70 255',
          'a key shows the blank keycap with its name: %r' % price[:10])
    hidden = [n for n in nat if n in ('set_visible 123cf8 0', 'set_visible 124108 0', 'set_visible 1253e0 0',
                                       'set_visible 123be0 0', 'set_visible 123510 0')]
    check(len(hidden) == 5 and 'set_visible 123fb0 0' not in nat and 'set_visible 125128 0' not in nat,
          'the price group other children (PRICE, other icons and amounts, background, border) are hidden: %r' % hidden)
    img, txt = lua.eval('BAR + 0x1968'), lua.eval('BAR + 0x2ae0')
    fl = lambda a, o: round(f.f32(a + o), 3)
    check((fl(img, 0x2c), fl(img, 0x30), fl(img, 0x3c), fl(img, 0x40), fl(img, 4), fl(img, 8), fl(img, 12), fl(img, 16))
          == (0, 0.5, 0.5, 0.5, 35, 0, 32, 32) and (fl(txt, 0x2c), fl(txt, 0x30), fl(txt, 4)) == (0, 0.5, 35),
          'keycap and name centered on the padlock (x 35) at the bar middle: anchor (0,0.5), pivot (0.5,0.5), 32x32')
    check('set_color 123fb0 1.00,1.00,1.00' in nat and 'set_color 125128 0.20,0.20,0.20' in nat,
          'native prompt colors: white keycap, dark gray name')
    variables = [n for n in nat if n.startswith('set_variable 123fb0')]
    check(variables == ['set_variable 123fb0 28723f4d 1,1,0.914,0',
                        'set_variable 123fb0 851fd4fd 1,0.929412,0.929412,0.929412',
                        'set_variable 123fb0 10c353af 0,0,0,0'],
          'the glyph material gets the prompt variables after set_image: %r' % variables)
    # The game's price refresh re-lays the icon out (right-aligned, 20x20): put back the next frame.
    lua.execute('fake.put(BAR + 0x1968 + 4, string.rep(string.char(0), 16)); fake.put(BAR + 0x1968 + 0x2c, '
                'string.rep(string.char(0), 4) .. string.char(0, 0, 0x80, 0x3f)); fake.natives = {}')
    f.frames(1)
    check((fl(img, 0x2c), fl(img, 0x30), fl(img, 4), fl(img, 12)) == (0, 0.5, 35, 32),
          'a refresh that moves the icon is undone the next frame: %r' % list(f.natives.values())[:6])
    f.frames(40)
    lua.execute('fake.reads = 0; fake.natives = {}')
    f.frames(10)
    print('INFO memory reads per frame in the Armory with the keycap shown: %.1f' % (f.reads / 10))
    check(len(f.natives) == 0, 'steady state: no native calls: %r' % list(f.natives.values())[:6])
    moves = [n for n in nat if n.startswith('set_position 122c28')]
    xs = [float(n.split()[2].split(',')[0]) for n in moves]
    check(len(xs) == 2 and abs(xs[1] - 2 * xs[0] - 8) < 1e-6,
          'with a glyph the text keeps its padlock margin plus an 8-unit gap: %r' % moves)
    check('set_layer 125128 1' in nat and f.i16(txt + 0xbc) == 1,
          'the key name draws over its keycap (layer + 1): %r' % [n for n in nat if 'set_layer' in n])
    # A gamepad button: a glyph texture.
    lua.execute('fake.mapping = fake.map(0x42, 0x10); fake.glyph_tex = 0x9587fdb00916c139ULL; fake.natives = {}')
    f.frames(12)
    nat = list(f.natives.values())
    check('set_image 123fb0 0xc0f3797849262087 0x9587fdb00916c139' in nat and 'set_visible 125128 0' in nat
          and f.glyph_query == '4 18 255',
          'with the pad in use, the pad button glyph, no key name: %r' % nat[:6])
    # Pad in use but only a key bound: no glyph (the pad can't press it).
    lua.execute('fake.bind({fake.map(0x43, 0x46)}); fake.natives = {}'); f.frames(12)
    check('Glyph: none, hidden' in log(), 'no pad binding while the pad is in use: no glyph')
    lua.execute('fake.bind({fake.map(0x43, 0x46), fake.map(0x42, 0x12)})'); f.frames(12)
    # A press of the binding equips as a click does.
    lua.execute('fake.natives = {}; fake.down = true'); f.frames(1); lua.execute('fake.down = false'); f.frames(1)
    nat = list(f.natives.values())
    check(any(n.startswith('commit') for n in nat) and 'Binding pressed' in log(), 'the binding equips the set: %r' % nat[:4])
    lua.execute('fake.natives = {}; fake.down = true'); f.frames(3)
    check(not any(n.startswith('commit') for n in f.natives.values()), 'a held binding equips once')
    lua.execute('fake.down = false'); f.frames(10)
    # Moving to an item without a set restores the price group.
    lua.execute('fake.natives = {}; fake.view(0x33333333)'); f.frames(3)
    nat = list(f.natives.values())
    check(all(('set_visible %s 1' % o) in nat for o in ('123cf8', '124108', '1253e0')),
          'restore: the hidden children are shown again: %r' % [n for n in nat if n.startswith('set_visible')])
    check('set_image 123fb0 0x57fcf14ad069020b 0x1234567890abcdef' in nat and 'set_label 125128 2004318071' in nat,
          'restore: the price icon and text get their own image and label back: %r'
          % [n for n in nat if '123fb0' in n or '125128' in n])
    # Revision 1 crash: set_image on a widget that isn't an image. A price icon of another type turns the glyph off.
    lua.execute('fake.put32(BAR + 0x1968, 0x141011); fake.natives = {}; fake.view(0x11111111)'); f.frames(40)
    lua.execute('fake.view(0x33333333)'); f.frames(3)
    nat = list(f.natives.values())
    check('Glyph off: price widgets of type 5/7' in log() and not any('123fb0' in n for n in nat),
          'a price icon that is not an image is never drawn on or restored: %r' % [n for n in nat if '123fb0' in n])
    lua.execute('fake.put32(BAR + 0x1968, 0x0c1011)')

    # Superstore set (price-tier rule): BFM-77 Reformer with its cape Tread of Liberty and its card.
    reformer = {'h': 0xede9d6b7, 'b': 0x3412f5e4, 'c': 0x1a0297e0, 'p': 0xcdea8cb2}
    lua.execute('fake.offers({{0x61000001, %d, true}, {0x61000002, %d, true}, {%d, %d, true}, {%d, %d, true, 9}, '
                '{0x33333333, %d, true}})' % (reformer['b'], reformer['h'], reformer['c'], reformer['c'],
                                               reformer['p'], reformer['p'], voidwalker))
    lua.execute('fake.put32(MGR + 0x166c, 0)'); f.frames(12)
    lua.execute('fake.open_armory(); fake.view(0x33333333)'); f.frames(3)
    lua.execute('fake.text = nil; fake.view(%d)' % reformer['c']); f.frames(3)
    check(f.text == 'EQUIP BFM-77 REFORMER SET (4/4)',
          'a Superstore cape and card joined to their armor by the price-tier rule: %r' % f.text)
    # A hand pairing (warbond page): Liberty's Herald with the FS-05 Marksman players own (v1 had it on an unowned copy).
    lua.execute('fake.offers({{0x62000001, 0xecabadbf, true}, {0x62000002, 0x529efe65, true}, '
                '{0xd45f0974, 0xd45f0974, true}, {0x33333333, %d, true}})' % voidwalker)
    lua.execute('fake.put32(MGR + 0x166c, 0)'); f.frames(12)
    lua.execute('fake.open_armory(); fake.view(0x33333333)'); f.frames(3)
    lua.execute('fake.text = nil; fake.view(0xd45f0974)'); f.frames(3)
    check(f.text == 'EQUIP FS-05 MARKSMAN SET (3/3)', 'a paired warbond cape joins the owned armor: %r' % f.text)
    check('Error' not in log(), 'no errors')
    print('%d/%d passed' % (sum(results), len(results)))
    return all(results)


if __name__ == '__main__':
    raise SystemExit(0 if main() else 1)
