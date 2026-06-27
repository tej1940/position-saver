---@diagnostic disable: undefined-global, undefined-field, missing-parameter, need-check-nil, missing-return, param-type-mismatch, lowercase-global

local app_folder   = ac.getFolder(ac.FolderID.ACApps) .. '/lua/position_saver/'
local save_file    = app_folder .. 'saves.ini'
local autosave_file = app_folder .. 'autosave.ini'

local sim    = ac.getSim()
local owncar = ac.getCar(0)
local vecDOWN = vec3(0,-1,0)

local COL = {
  green     = rgbm(0.2, 0.85, 0.3, 1),
  green_dim = rgbm(0.05,0.35, 0.1, 1),
  red       = rgbm(0.9, 0.2,  0.2, 1),
  red_dim   = rgbm(0.4, 0.07, 0.07,1),
  blue      = rgbm(0.25,0.55, 1,   1),
  blue_dim  = rgbm(0.08,0.2,  0.45,1),
  orange    = rgbm(1,   0.6,  0.1, 1),
  gray      = rgbm(0.45,0.45, 0.45,1),
  gray_dark = rgbm(0.2, 0.2,  0.2, 1),
  white     = rgbm(1,   1,    1,   1),
  yellow    = rgbm(1,   0.88, 0.1, 1),
}

local NUM_SLOTS   = 10
local selected    = 1
local saves       = {}
local feedback    = { msg='', col=COL.white, timer=0 }
local confirm_del = nil
local name_buf    = {}
for i = 1, NUM_SLOTS do name_buf[i] = '' end

-- Autosave
local settings = ac.storage({ autosaveTracks = '', language = 'fr' }, 'position_saver_settings')
settings.language = settings.language or 'fr'

local translations = {
  fr = {
    language_label = 'Langue :',
    language_changed = 'Langue définie sur %s',
    french = 'Français',
    english = 'Anglais',
    track = 'Circuit : ',
    autosave_circuit = 'Autosave circuit',
    enable_on_track = 'Activer sur ce circuit',
    autosave_enabled = 'Autosave activé sur %s',
    autosave_disabled = 'Autosave désactivé sur %s',
    autosave_tooltip = 'Sauvegarde ta position en quittant ce circuit\net te téléporte au retour',
    last_save = 'Dernière sauvegarde : ',
    no_save = 'Aucune sauvegarde encore (quitte le circuit pour en créer une)',
    slot = 'Slot ',
    empty = ' : vide',
    empty_slot_tooltip = 'Slot vide',
    optional_name_tooltip = 'Nom optionnel (laisser vide = nom auto)',
    save = 'Sauvegarder',
    teleport = 'Téléporter',
    slot_saved = 'Slot %d sauvegardé : %s',
    slot_empty_msg = 'Slot %d est vide !',
    warning_other_track = 'Attention : position d\'un autre circuit !',
    slot_deleted = 'Slot %d supprimé',
    delete = 'Supprimer',
    delete_question = 'Supprimer "%s" ?',
    confirm = 'Confirmer',
    cancel = 'Annuler',
    autosave_repositioned = 'Autosave : repositionné sur %s',
    teleport_to = 'Teleporté vers "%s"',
  },
  en = {
    language_label = 'Language:',
    language_changed = 'Language set to %s',
    french = 'French',
    english = 'English',
    track = 'Track : ',
    autosave_circuit = 'Track autosave',
    enable_on_track = 'Enable on this track',
    autosave_enabled = 'Autosave enabled on %s',
    autosave_disabled = 'Autosave disabled on %s',
    autosave_tooltip = 'Save your position when leaving this track\nand teleport you back on return',
    last_save = 'Last save: ',
    no_save = 'No autosave yet (leave the track to create one)',
    slot = 'Slot ',
    empty = ' : empty',
    empty_slot_tooltip = 'Empty slot',
    optional_name_tooltip = 'Optional name (leave blank = auto name)',
    save = 'Save',
    teleport = 'Teleport',
    slot_saved = 'Slot %d saved: %s',
    slot_empty_msg = 'Slot %d is empty !',
    warning_other_track = 'Warning: position from another track !',
    slot_deleted = 'Slot %d deleted',
    delete = 'Delete',
    delete_question = 'Delete "%s" ?',
    confirm = 'Confirm',
    cancel = 'Cancel',
    autosave_repositioned = 'Autosave: repositioned to %s',
    teleport_to = 'Teleported to "%s"',
  },
}

local function tr(key, ...)
  local lang = settings.language or 'fr'
  local text = translations[lang] and translations[lang][key] or translations.fr[key] or key
  if select('#', ...) > 0 then
    return string.format(text, ...)
  end
  return text
end

local function setLanguage(lang)
  if lang ~= 'fr' and lang ~= 'en' then return end
  settings.language = lang
  notify(tr('language_changed', tr(lang == 'fr' and 'french' or 'english')), COL.green)
end

local function languageButton(lang_code)
  local active = settings.language == lang_code
  if active then
    ui.pushStyleColor(ui.StyleColor.Button, COL.blue_dim)
    ui.pushStyleColor(ui.StyleColor.ButtonHovered, COL.blue)
  end
  local clicked = ui.button(lang_code, vec2(40, 22))
  if active then ui.popStyleColor(2) end
  return clicked
end

local autosave_tracks = {}
local prev_track      = ''
local auto_tp_done    = false
local auto_tp_timer   = 0
local last_cache      = { track = '' }
local init_done       = false

local function notify(msg, col)
  feedback.msg   = msg
  feedback.col   = col or COL.white
  feedback.timer = 3.5
end

local function trackSection(id)
  return 'AUTO_' .. id:gsub('[^%w_%-]', '_')
end

local function reloadAutosaveTracks()
  autosave_tracks = {}
  if settings.autosaveTracks ~= '' then
    for id in settings.autosaveTracks:gmatch('[^|]+') do
      autosave_tracks[id] = true
    end
  end
end

local function saveAutosaveTrackList()
  local list = {}
  for id in pairs(autosave_tracks) do table.insert(list, id) end
  table.sort(list)
  settings.autosaveTracks = table.concat(list, '|')
end

local function isAutosaveTrack(id)
  return autosave_tracks[id] == true
end

local function setAutosaveTrack(id, enabled)
  if enabled then autosave_tracks[id] = true else autosave_tracks[id] = nil end
  saveAutosaveTrackList()
end

-- ── Persistance slots ─────────────────────────────────────────────────────────
local function loadSaves()
  saves = {}
  if not io.exists(save_file) then return end
  local ini = ac.INIConfig.load(save_file, ac.INIFormat.Extended)
  for i = 1, NUM_SLOTS do
    local k    = 'SLOT_' .. i
    local name = ini:get(k, 'NAME', '')
    if name ~= '' then
      saves[i] = {
        name  = name,
        pos   = vec3(ini:get(k,'POS_X',0), ini:get(k,'POS_Y',0), ini:get(k,'POS_Z',0)),
        dir   = vec3(ini:get(k,'DIR_X',0), 0, ini:get(k,'DIR_Z',1)),
        track = ini:get(k, 'TRACK', ''),
        date  = ini:get(k, 'DATE',  ''),
      }
    end
  end
end

local function writeSaves()
  local lines = {}
  for i = 1, NUM_SLOTS do
    local s = saves[i]
    if s then
      local k = 'SLOT_' .. i
      table.insert(lines, '[' .. k .. ']')
      table.insert(lines, 'NAME='  .. s.name)
      table.insert(lines, 'POS_X=' .. string.format('%.4f', s.pos.x))
      table.insert(lines, 'POS_Y=' .. string.format('%.4f', s.pos.y))
      table.insert(lines, 'POS_Z=' .. string.format('%.4f', s.pos.z))
      table.insert(lines, 'DIR_X=' .. string.format('%.4f', s.dir.x))
      table.insert(lines, 'DIR_Z=' .. string.format('%.4f', s.dir.z))
      table.insert(lines, 'TRACK=' .. s.track)
      table.insert(lines, 'DATE='  .. s.date)
      table.insert(lines, '')
    end
  end
  io.save(save_file, table.concat(lines, '\n'))
end

-- ── Persistance autosave ──────────────────────────────────────────────────────
local function loadAllAutosaves()
  local all = {}
  if not io.exists(autosave_file) then return all end
  local ini = ac.INIConfig.load(autosave_file, ac.INIFormat.Extended)
  for line in io.load(autosave_file):gmatch('[^\r\n]+') do
    local sec = line:match('^%[(.+)%]$')
    if sec and ini:get(sec, 'NAME', '') ~= '' then
      all[sec] = {
        name  = ini:get(sec, 'NAME', ''),
        pos   = vec3(ini:get(sec,'POS_X',0), ini:get(sec,'POS_Y',0), ini:get(sec,'POS_Z',0)),
        dir   = vec3(ini:get(sec,'DIR_X',0), 0, ini:get(sec,'DIR_Z',1)),
        track = ini:get(sec, 'TRACK', ''),
        date  = ini:get(sec, 'DATE', ''),
      }
    end
  end
  return all
end

local function loadAutosaveData(trackId)
  local sec = trackSection(trackId)
  return loadAllAutosaves()[sec]
end

local function writeAutosaveData(data)
  local all = loadAllAutosaves()
  all[trackSection(data.track)] = data
  local lines = {}
  for sec, s in pairs(all) do
    table.insert(lines, '[' .. sec .. ']')
    table.insert(lines, 'NAME='  .. s.name)
    table.insert(lines, 'POS_X=' .. string.format('%.4f', s.pos.x))
    table.insert(lines, 'POS_Y=' .. string.format('%.4f', s.pos.y))
    table.insert(lines, 'POS_Z=' .. string.format('%.4f', s.pos.z))
    table.insert(lines, 'DIR_X=' .. string.format('%.4f', s.dir.x))
    table.insert(lines, 'DIR_Z=' .. string.format('%.4f', s.dir.z))
    table.insert(lines, 'TRACK=' .. s.track)
    table.insert(lines, 'DATE='  .. s.date)
    table.insert(lines, '')
  end
  io.save(autosave_file, table.concat(lines, '\n'))
end

local function writeAutosaveFromCache(cache)
  if cache.track == '' or not cache.pos then return end
  writeAutosaveData({
    name  = cache.name or (ac.getTrackName() .. ' (auto)'),
    pos   = cache.pos,
    dir   = cache.dir,
    track = cache.track,
    date  = cache.date or os.date('%d/%m %H:%M'),
  })
end

local function autosaveCurrentTrack(trackId)
  local car = ac.getCar(0)
  if not car or not car.physicsAvailable then return end
  writeAutosaveData({
    name  = (ac.getTrackName() or trackId) .. ' (auto)',
    pos   = vec3(car.position.x, car.position.y, car.position.z),
    dir   = vec3(car.look.x, 0, car.look.z),
    track = trackId,
    date  = os.date('%d/%m %H:%M'),
  })
end

-- ── Teleport ──────────────────────────────────────────────────────────────────
local function teleportToSave(s, quiet)
  if not s then return false end
  if not owncar.physicsAvailable then return false end
  local probe = vec3(s.pos.x, s.pos.y + 5, s.pos.z)
  local hit   = physics.raycastTrack(probe, vecDOWN, 30)
  local fy    = (hit ~= -1) and ((s.pos.y + 5) - hit + 0.15) or s.pos.y
  local look  = vec3(s.dir.x, 0, s.dir.z)
  if look:length() < 0.01 then look = vec3(0,0,1) end
  physics.setCarPosition(0, vec3(s.pos.x, fy, s.pos.z), -look)
  if not quiet then notify(tr('teleport_to', s.name), COL.green) end
  return true
end

-- ── Actions slots ─────────────────────────────────────────────────────────────
local function saveSlot(slot)
  local car  = ac.getCar(sim.focusedCar)
  local name = (name_buf[slot] and name_buf[slot] ~= '')
               and name_buf[slot]
               or  (ac.getTrackName() .. ' #' .. slot)
  saves[slot] = {
    name  = name,
    pos   = vec3(car.position.x, car.position.y, car.position.z),
    dir   = vec3(car.look.x,     0,              car.look.z),
    track = ac.getTrackFullID('/'),
    date  = os.date('%d/%m %H:%M'),
  }
  writeSaves()
  name_buf[slot] = ''
  notify(tr('slot_saved', slot, name), COL.green)
end

local function teleportSlot(slot)
  local s = saves[slot]
  if not s then notify(tr('slot_empty_msg', slot), COL.red) return end
  if s.track ~= '' and s.track ~= ac.getTrackFullID('/') then
    notify(tr('warning_other_track'), COL.orange)
  end
  teleportToSave(s)
end

local function deleteSlot(slot)
  saves[slot] = nil
  writeSaves()
  notify(tr('slot_deleted', slot), COL.gray)
  confirm_del = nil
end

reloadAutosaveTracks()
loadSaves()

-- ── UI helper ─────────────────────────────────────────────────────────────────
local function colorBtn(label, col, col_hov, size)
  ui.pushStyleColor(ui.StyleColor.Button,        col)
  ui.pushStyleColor(ui.StyleColor.ButtonHovered, col_hov or col)
  local r = ui.button(label, size or vec2(0,0))
  ui.popStyleColor(2)
  return r
end

local function slotRowLabel(i, s, W)
  local name   = s and s.name or tr('empty')
  local badge  = (s and s.track ~= '' and s.track ~= ac.getTrackFullID('/') and '  [!]' or '')
  local date   = s and s.date or ''
  local label  = string.format('[%02d]  %s%s', i, name, badge)
  if date ~= '' then
    local labelW = ui.measureText(label).x
    local dateW  = ui.measureText(date).x
    local spaceW = ui.measureText(' ').x
    local pad    = math.floor((W - 16 - labelW - dateW) / spaceW)
    if pad > 0 then label = label .. string.rep(' ', pad) end
    label = label .. date
  end
  return label
end

-- ── script.update : autosave + auto-teleport ──────────────────────────────────
function script.update(dt)
  if not init_done then
    init_done = true
    ac.onRelease(function()
      if last_cache.track ~= '' and isAutosaveTrack(last_cache.track) then
        writeAutosaveFromCache(last_cache)
      end
    end)
  end

  local track = ac.getTrackFullID('/')
  local car   = ac.getCar(0)

  if prev_track ~= '' and prev_track ~= track then
    if isAutosaveTrack(prev_track) then
      if last_cache.track == prev_track then
        writeAutosaveFromCache(last_cache)
      else
        autosaveCurrentTrack(prev_track)
      end
    end
    auto_tp_done  = false
    auto_tp_timer = 0
  end

  if track ~= '' and isAutosaveTrack(track) and car.physicsAvailable then
    last_cache = {
      track = track,
      name  = (ac.getTrackName() or track) .. ' (auto)',
      pos   = vec3(car.position.x, car.position.y, car.position.z),
      dir   = vec3(car.look.x, 0, car.look.z),
      date  = os.date('%d/%m %H:%M'),
    }
  end

  if not auto_tp_done and track ~= '' and isAutosaveTrack(track) then
    local saved = loadAutosaveData(track)
    if saved and car.physicsAvailable then
      auto_tp_timer = auto_tp_timer + dt
      if auto_tp_timer >= 0.8 then
        if teleportToSave(saved, true) then
          auto_tp_done = true
          notify('Autosave : repositionne sur ' .. (ac.getTrackName() or track), COL.blue)
        end
      end
    end
  end

  prev_track = track
end

-- ── Fenêtre principale ────────────────────────────────────────────────────────
function script.windowMain(dt)
  owncar = ac.getCar(0)
  if feedback.timer > 0 then feedback.timer = feedback.timer - dt end

  local W = ui.windowSize().x
  local currentTrack = ac.getTrackFullID('/')
  local trackName    = ac.getTrackName() or '?'

  ui.textColored(tr('language_label'), COL.gray)
  ui.sameLine()
  if languageButton('FR') then setLanguage('fr') end
  ui.sameLine()
  if languageButton('EN') then setLanguage('en') end
  ui.offsetCursorY(6)

  ui.textColored(tr('track') .. trackName, COL.gray)

  -- Autosave
  ui.offsetCursorY(4)
  ui.textColored(tr('autosave_circuit'), COL.yellow)
  local autosaveOn = isAutosaveTrack(currentTrack)
  if ui.checkbox(tr('enable_on_track'), autosaveOn) then
    setAutosaveTrack(currentTrack, not autosaveOn)
    if not autosaveOn then
      notify(tr('autosave_enabled', trackName), COL.green)
    else
      notify(tr('autosave_disabled', trackName), COL.gray)
    end
  end
  if ui.itemHovered() then
    ui.setTooltip(tr('autosave_tooltip'))
  end

  if autosaveOn then
    local auto = loadAutosaveData(currentTrack)
    if auto then
      ui.textColored(tr('last_save') .. auto.date, COL.gray)
    else
      ui.textColored(tr('no_save'), COL.gray_dark)
    end
  end

  ui.separator()

  -- Feedback
  if feedback.timer > 0 then
    ui.textColored(feedback.msg, feedback.col)
    ui.separator()
  end

  -- ── Slots scrollables ──
  ui.beginChild('slots_list', vec2(0, 210), true)
  for i = 1, NUM_SLOTS do
    local s      = saves[i]
    local is_sel = (selected == i)
    local label  = slotRowLabel(i, s, W)

    if is_sel then
      ui.pushStyleColor(ui.StyleColor.Header,        rgbm(0.35, 0.30, 0.05, 0.55))
      ui.pushStyleColor(ui.StyleColor.HeaderHovered, rgbm(0.45, 0.38, 0.08, 0.65))
      ui.pushStyleColor(ui.StyleColor.HeaderActive,  rgbm(0.50, 0.42, 0.10, 0.75))
    end

    if ui.selectable(label .. '##slot' .. i, is_sel) then
      selected = i
      confirm_del = nil
    end

    if is_sel then ui.popStyleColor(3) end
  end
  ui.endChild()

  ui.separator()

  -- ── Panneau actions slot sélectionné ──
  local s = saves[selected]
  ui.textColored(tr('slot') .. selected .. (s and (' : ' .. s.name) or tr('empty')), COL.yellow)
  ui.offsetCursorY(8)

  name_buf[selected] = ui.inputText('##n' .. selected, name_buf[selected] or '', 64)
  if ui.itemHovered() then ui.setTooltip(tr('optional_name_tooltip')) end
  ui.offsetCursorY(8)

  local bw = (W - 20) / 2
  if colorBtn(tr('save'), COL.green_dim, COL.green, vec2(bw, 26)) then
    saveSlot(selected)
  end

  ui.sameLine()

  if s then
    if colorBtn(tr('teleport'), COL.blue_dim, COL.blue, vec2(bw, 26)) then
      teleportSlot(selected)
    end
  else
    ui.pushStyleColor(ui.StyleColor.Button,        COL.gray_dark)
    ui.pushStyleColor(ui.StyleColor.ButtonHovered, COL.gray_dark)
    ui.button(tr('teleport'), vec2(bw, 26))
    ui.popStyleColor(2)
    if ui.itemHovered() then ui.setTooltip(tr('empty_slot_tooltip')) end
  end

  if s then
    ui.offsetCursorY(8)
    if confirm_del == selected then
      ui.textColored(string.format(tr('delete_question'), s.name), COL.red)
      if colorBtn(tr('confirm'), COL.red_dim, COL.red, vec2(100, 22)) then deleteSlot(selected) end
      ui.sameLine()
      if ui.button(tr('cancel'), vec2(70, 22)) then confirm_del = nil end
    else
      if colorBtn(tr('delete'), COL.red_dim, COL.red, vec2(90, 22)) then confirm_del = selected end
    end
  end
end
