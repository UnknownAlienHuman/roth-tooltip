local _, addon = ...

addon.db = {
    version = 3.1,
    general = {
        scale             = 1,                      --縮放
        mask              = true,                   --頂部遮罩層
        bgfile            = "RothTooltipDarkTexture",                 --背景
        background        = {0, 0, 0, 0.90},         --背景顔色和透明度
        borderSize        = 1,                      --邊框大小（直角邊框才生效）
        borderCorner      = "RothTooltipDarkFrame",              --邊框類型 default|angular:直角邊框
        borderColor       = {0.6, 0.6, 0.6, 0.85},   --邊框顔色和透明度
        statusbarHeight   = 4,                      --HP高度
        statusbarPosition = "bottom",               --HP位置 default|bottom|top
        statusbarOffsetX  = 0,                      --HP X偏移 0:自動
        statusbarOffsetY  = 0,                      --HP Y偏移 0:自動
        statusbarFontSize = 10,                     --HP文字大小
        statusbarFontFlag = "THINOUTLINE",          --HP文字樣式
        statusbarText     = true,                   --HP文字
        statusbarTextFormat = "health/max",         --HP формат: health/max|percent|health (percent)|none
        statusbarColor    = "auto",                 --HP顔色 default|auto|smooth
        statusbarTexture  = "Interface\\AddOns\\RothTooltip\\texture\\StatusBar", --HP材質
        anchor            = { position = "cursorRight", hiddenInCombat = false, returnInCombat = true, returnOnUnitFrame = false, cp = "BOTTOM", p = "BOTTOMRIGHT", }, --鼠標位置 default|cursor|static|cursorRight
        alwaysShowIdInfo  = true,
        skinMoreFrames    = true,
        visibility = {
            inCombat = "show",     -- show|hide|unitOnly
            inRaid   = "show",     -- show|hide
            inArena  = "show",     -- show|hide
            bags     = "show",     -- show|hide
            actionBars = "show",   -- show|hide
        },

        combatPolicy      = "STRICT",              -- combat write policy: STRICT|BALANCED|AGGRESSIVE
        headerFont        = "default",
        headerFontSize    = "default",
        headerFontFlag    = "default",
        bodyFont          = "default",
        bodyFontSize      = "default",
        bodyFontFlag      = "default",
        SavedVariablesPerCharacter = false,
    },
    unit = {
        player = {
            coloredBorder = "class",                --玩家邊框顔色 default|class|level|reaction|itemQuality|selection|faction|HEX
            background = { colorfunc = "class", alpha = 0.9, },
            anchor = { position = "inherit", hiddenInCombat = false, returnInCombat = false, returnOnUnitFrame = false, cp = "BOTTOM", p = "BOTTOMRIGHT", },
            showTarget = true,                      --顯示目標
            showTargetBy = true,                    --顯示被關注
            showModel = true,                       --顯示模型
            grayForDead = false,                    --灰色死亡目標
            showItemLevel = true,                   --顯示自身平均裝等 (tooltip:unit)
            showPveScore  = true,                   --顯示自身 Mythic+ 分數 (tooltip:unit)
            showBestKey   = true,                   --顯示最佳完成的 Mythic+ 鑰匙 (tooltip:unit)
            showRaidProgress = true,                --顯示當前團隊副本進度 (tooltip:unit)
            elements = {
                raidIcon    = { enable = true, filter = "none" },
                roleIcon    = { enable = true, filter = "none" },
                pvpIcon     = { enable = true, filter = "none" },
                factionIcon = { enable = true, filter = "none" },
                factionBig  = { enable = true, filter = "none" },
                classIcon   = { enable = true, filter = "none" },
                friendIcon  = { enable = true, filter = "none" },
                title       = { enable = true, color = "ccffff", wildcard = "%s",   filter = "none" },
                name        = { enable = true, color = "class",  wildcard = "%s",   filter = "none" },
                realm       = { enable = true, color = "00eeee", wildcard = "%s",   filter = "none" },
                statusAFK   = { enable = true, color = "ffd200", wildcard = "(%s)", filter = "none" },
                statusDND   = { enable = true, color = "ffd200", wildcard = "(%s)", filter = "none" },
                statusDC    = { enable = true, color = "999999", wildcard = "(%s)", filter = "none" },
                guildName   = { enable = true, color = "ff00ff", wildcard = "<%s>", filter = "none" },
                guildIndex  = { enable = false, color = "cc88ff", wildcard = "%s",  filter = "none" },
                guildRank   = { enable = true, color = "cc88ff", wildcard = "(%s)", filter = "none" },
                guildRealm  = { enable = true, color = "00cccc", wildcard = "%s",   filter = "none" },
                levelValue  = { enable = true, color = "level",   wildcard = "%s",  filter = "none" }, 
                factionName = { enable = true, color = "faction", wildcard = "%s",  filter = "none" }, 
                gender      = { enable = false, color = "999999",  wildcard = "%s", filter = "none" }, 
                raceName    = { enable = true, color = "cccccc",  wildcard = "%s",  filter = "none" }, 
                className   = { enable = true, color = "ffffff",  wildcard = "%s",  filter = "none" }, 
                isPlayer    = { enable = false, color = "ffffff",  wildcard = "(%s)", filter = "none" }, 
                role        = { enable = false, color = "ffffff",  wildcard = "(%s)", filter = "none" },
                moveSpeed   = { enable = false, color = "e8e7a8",  wildcard = "%d%%", filter = "none" },
                zone        = { enable = true,  color = "ffffff",  wildcard = "%s", filter = "none" },
                { "friendIcon", "raidIcon", "roleIcon", "pvpIcon", "factionIcon", "classIcon", "title", "name", "realm", "statusAFK", "statusDND", "statusDC", },
                { "guildName", "guildIndex", "guildRank", "guildRealm", },
                { "levelValue", "factionName", "gender", "raceName", "className", "isPlayer", "role", "moveSpeed", },
                { "zone" },
            },
        },
        npc = {
            coloredBorder = "reaction",
            background = { colorfunc = "default", alpha = 0.9, },
            showTarget = true,
            showTargetBy = true,
            grayForDead = false,
            showModel = true,
            anchor = { position = "inherit", hiddenInCombat = false, returnInCombat = false, returnOnUnitFrame = false, cp = "BOTTOM", p = "BOTTOMRIGHT", },
            elements = {
                factionBig   = { enable = false, filter = "none" },
                raidIcon     = { enable = true,  filter = "none" },
                classIcon    = { enable = false, filter = "none" },
                questIcon    = { enable = true,  filter = "none" },
                name         = { enable = true, color = "default",wildcard = "%s",    filter = "none" },
                npcTitle     = { enable = true, color = "99e8e8", wildcard = "<%s>",  filter = "none" },
                levelValue   = { enable = true, color = "level",  wildcard = "%s",    filter = "none" }, 
                classifBoss  = { enable = true, color = "ff0000", wildcard = "(%s)",  filter = "none" },
                classifElite = { enable = true, color = "ffff33", wildcard = "(%s)",  filter = "none" }, 
                classifRare  = { enable = true, color = "ffaaff", wildcard = "(%s)",  filter = "none" }, 
                creature     = { enable = true, color = "selection", wildcard = "%s", filter = "none" },
                reactionName = { enable = true, color = "33ffff", wildcard = "<%s>",  filter = "reaction6" },
                moveSpeed    = { enable = false, color = "e8e7a8",  wildcard = "%d%%", filter = "none" },
                { "raidIcon", "classIcon", "questIcon", "name", },
                { "levelValue", "classifBoss", "classifElite", "classifRare", "creature", "reactionName", "moveSpeed", },
            },
        },
    },
    item = {
        coloredItemBorder = true,  --邊框按品質染色
        showItemIcon = true,       --物品圖標
        showStackCount = false,    --堆疊上限
        showItemID = false,        --顯示物品 ID
        showExpansionInfo = true,  --показывать эпоху предмета
    },
    spell = {
        showIcon = true,
    },
    quest = {
        coloredQuestBorder = true,  --任務按等差染色
    },
    model = {
        width   = 100,
        height  = 100,
        facing  = -0.25,
        offsetX = 8,
        offsetY = -16,
    },
    -- Engine/module switches. Used by ModuleManager to lazily attach hooks.
    -- NOTE: General is a core module and will always be enabled at load.
    modules = {
        General    = true,
        Anchor     = true,
        Target     = true,
        Unit       = true,
        Model      = true,
        Item       = true,
        Spell      = true,
        Quest      = true,
        LinkID     = true,
        Mount         = true,
        ExpansionInfo = true,
        SkinFrames    = true,
    },
    variables = {}, --用户配置数据
}
