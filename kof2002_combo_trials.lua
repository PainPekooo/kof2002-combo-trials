-- KOF 2002 - Combo Trials para FBNeo / Fightcade  (BETA)
-- Fase beta: la mayoria de los combos no estan probados en el juego real con
-- todos los personajes. Si uno no sale, reportalo o corrigelo en la lista CHARS.
-- Uso: se carga solo como addon del training mode de Fightcade, o a mano:
--      Game > Lua Scripting > New Lua Script Window > Browse > este archivo > Run
-- Juega en el lado P1.
-- Controles (manten Start):
--   Start + Arriba/Abajo     cambiar personaje
--   Start + Izq/Der          cambiar combo
--   Start + A                combos / rekkas (solo personajes con lista de rekkas)
--   Start + C                modo compacto / completo / oculto
--   Start + D                reiniciar el intento
-- Notacion: numpad / KOF clasica, siempre relativa a hacia donde mira P1.

----------------------------------------------------------------------------
-- Memoria (direcciones tomadas de peon2/fbneo-training-mode, kof2002.lua)
----------------------------------------------------------------------------
local ADDR = {
	p1_facing = 0x108131, -- 0 = mirando a la izquierda
	p1_hits   = 0x1084B0, -- hits que P1 lleva conectados en el combo actual
	p2_health = 0x108439,
	p1_stock  = 0x1082E3,
	p1_bar    = 0x1081E8,
	timer     = 0x10A7D2, -- palabra (2 bytes); 0x6000 = reloj lleno
}
local TIMER_FULL = 0x6000
local P2_MAX_HEALTH = 0x65
local STOCK_FILL    = 3

local rb, wb = memory.readbyte, memory.writebyte

----------------------------------------------------------------------------
-- Ajustes de lectura de inputs (en frames)
----------------------------------------------------------------------------
local MOTIONS = {
	qcf    = {2, 3, 6},
	qcb    = {2, 1, 4},
	dp     = {6, 2, 3},
	rdp    = {4, 2, 1},
	hcf    = {4, 1, 2, 3, 6},
	hcb    = {6, 3, 2, 1, 4},
	qcfx2  = {2, 3, 6, 2, 3, 6},
	qcbx2  = {2, 1, 4, 2, 1, 4},
	hcfx2  = {4, 1, 2, 3, 6, 4, 1, 2, 3, 6},
	hcbx2  = {6, 3, 2, 1, 4, 6, 3, 2, 1, 4},
	qcfx4  = {2, 3, 6, 2, 3, 6, 2, 3, 6, 2, 3, 6},
	qcfhcb = {2, 3, 6, 3, 2, 1, 4},
	qcbhcf = {2, 1, 4, 1, 2, 3, 6},
	fhcf   = {6, 4, 1, 2, 3, 6},
	hcbf   = {6, 3, 2, 1, 4, 6},
	bdp    = {4, 6, 2, 3},
	fbf    = {6, 4, 6},
	qcfuf  = {2, 3, 6, 9},
	dd     = {2, 5, 2},
	du     = {2, 8},
	ff     = {6, 5, 6},
}
-- ventana por defecto: 8 + 6 frames por direccion
local WINDOW = { dd = 20, du = 16, ff = 14 }
for name, seq in pairs(MOTIONS) do WINDOW[name] = WINDOW[name] or 8 + 6 * #seq end

local function isDown(d) return d == 1 or d == 2 or d == 3 end
local function isUp(d) return d == 7 or d == 8 or d == 9 end
local function isBack(d) return d == 1 or d == 4 or d == 7 end
local function isFwd(d) return d == 3 or d == 6 or d == 9 end
local CHARGES = {
	["[2]8"] = { from = isDown, to = isUp,  icons = {2, 8} },
	["[4]6"] = { from = isBack, to = isFwd, icons = {4, 6} },
}
local DIRS = { f = {6}, b = {4}, d = {1, 2, 3}, u = {7, 8, 9}, df = {3}, db = {1}, uf = {9}, ub = {7} }
local DIR_ICON = { f = 6, b = 4, d = 2, u = 8, df = 3, db = 1, uf = 9, ub = 7 }

local CHARGE_FRAMES = 30   -- frames de carga
local SIMUL         = 3    -- frames de tolerancia para botones "a la vez"
local FIRST_HIT_MAX = 60   -- frames para que conecte el primer golpe
local LAST_HIT_MAX  = 120  -- frames para que conecte el ultimo paso
local FAIL_FRAMES   = 15   -- cuanto queda en rojo el paso fallado antes de reiniciar
local OK_FRAMES     = 45   -- cuanto queda en verde el combo logrado
local HISTORY       = 600  -- frames de inputs guardados (alcanza para grabar un combo)

----------------------------------------------------------------------------
-- Combos por personaje: { barras, "notacion" }
-- Pasos separados por coma; ":Nombre" opcional al final de cada paso.
--   cl.C / st.B / far D / B  boton sin direccion     cr.A  abajo + boton
--   f+B  df+C  uf+D ...      direccion + boton       66    correr
--   qcf+A  dp+C  hcb f+P...  movimiento + boton      [2]8+D / [4]6+C  carga
--   P = A o C, K = B o D, "A/C" cualquiera, "AC" a la vez
-- Opcional: rekkas = { ... } con el mismo formato, para el modo rekka (Start + A).
-- Fuentes: Dream Cancel wiki (paginas de KOF 2002 y de 2002 UM filtradas a
-- movimientos que existen en 2002). Si un combo no sale en 2002, cambiarlo aqui.
----------------------------------------------------------------------------
local CHARS = {
	{ name = "Kim", combos = {
		{ 0, "cl.C, qcb+D:Hangetsuzan" },
		{ 0, "cl.C, qcb+C:Sankuu Kyaku, uf+D, d+D" },
		{ 0, "cr.B, cr.A, qcb+C:Sankuu Kyaku, uf+D, d+D" },
		{ 1, "cl.C, qcb hcf+K:Hou'ou Kyaku" },
		{ 1, "cl.C, qcfx2+D:Hou'ou Hiten Kyaku, [2]8+D:Hien Zan, d+D:Tenshou Zan" },
		{ 2, "cl.C, qcb+B:Hangetsuzan, qcfx2+D:Hou'ou Hiten Kyaku, [2]8+D:Hien Zan, d+D:Tenshou Zan" },
		{ 2, "f+B:Neri Chagi, BC:MAX, 66, cl.C, qcfx2+D:Hou'ou Hiten Kyaku, [2]8+D:Hien Zan, d+D:Tenshou Zan" },
	}, rekkas = {
		{ 0, "qcb+A:Sanren Geki 1, qcb+A:Sanren Geki 2, qcb+A:Sanren Geki 3" },
		{ 0, "qcb+C:Sanren Geki 1, qcb+C:Sanren Geki 2, qcb+C:Sanren Geki 3" },
		{ 0, "qcb+C:Sankuu Kyaku 1, uf+D:Sankuu Kyaku 2, d+D:Sankuu Kyaku 3" },
		{ 0, "cl.C, qcb+A:Sanren Geki 1, qcb+A:Sanren Geki 2, qcb+A:Sanren Geki 3" },
		{ 0, "cr.B, cr.A, qcb+A:Sanren Geki 1, qcb+A:Sanren Geki 2, qcb+A:Sanren Geki 3" },
		{ 2, "f+B:Neri Chagi, BC:MAX, 66, cl.C, qcb+C:Sanren Geki 1, qcb+C:Sanren Geki 2, qcb+D:Hangetsuzan, [2]8+D:Hien Zan, d+D:Tenshou Zan" },
		{ 3, "f+B:Neri Chagi, BC:MAX, 66, cl.C, qcb+A:Sanren Geki 1, qcb+A:Sanren Geki 2, qcb+A:Sanren Geki 3, qcb+B:Hangetsuzan, qcfx2+D:Hou'ou Hiten Kyaku, [2]8+D:Hien Zan, d+D:Tenshou Zan" },
	}},
	{ name = "Kyo", combos = {
		{ 0, "cl.C, qcf+C:Dokugami, hcb+C:Tsumi Yomi, f+C:Batsu Yomi, dp+C:Oniyaki" },
		{ 0, "cl.C, df+D:88 Shiki, qcf+C:Dokugami, hcb+C:Tsumi Yomi, f+C:Batsu Yomi" },
		{ 1, "cl.C, qcb hcf+A:Orochinagi" },
	}},
	{ name = "Benimaru", combos = {
		{ 0, "cr.B, cr.B, B" },
		{ 0, "cr.B, qcf+D:Iai Geri, du+B:Handou Sandan Geri" },
		{ 0, "cl.D, qcb+A:Shinkuu Katategoma" },
		{ 1, "cr.B, cr.B, qcfx2+A:Raikou Ken" },
		{ 2, "cl.D, qcb+C:Shinkuu Katategoma, qcbx2+B:Gen'ei Hurricane" },
	}},
	{ name = "Daimon", combos = {
		{ 0, "cl.C, hcb f+C:Tenchi Gaeshi" },
		{ 0, "cr.A, hcb f+C:Tenchi Gaeshi" },
		{ 0, "cl.C, hcf+C:Kirikabu Gaeshi" },
		{ 1, "cl.C, df+C:Zujou Barai, hcbx2+A:Jigoku Gokuraku Otoshi" },
		{ 3, "cl.C, BC:MAX, 66, cl.C, hcbx2+AC:Jigoku Gokuraku (SDM)" },
	}},
	{ name = "Terry", combos = {
		{ 0, "cl.C, qcb+A:Burn Knuckle" },
		{ 0, "cr.B, cr.A, dp+D:Power Dunk" },
		{ 0, "cr.B, cr.A, [2]8+C:Rising Tackle" },
		{ 1, "cl.C, qcb hcf+A:Power Geyser" },
	}},
	{ name = "Andy", combos = {
		{ 0, "cr.B, B, dp+C:Shouryuu Dan" },
		{ 0, "cr.B, df+A:Age Men, qcb+A:Hishou Ken" },
		{ 1, "cr.B, cr.A, df+A:Age Men, qcb hcf+A:Zan'ei Ryuusei Ken" },
	}},
	{ name = "Joe", combos = {
		{ 0, "cl.C, hcf+B:Slash Kick" },
		{ 1, "cr.B, cr.A, qcf hcb+A:Bakuretsu Hurricane" },
		{ 1, "cl.C, qcf uf+B:Ougon no Tiger Kick" },
	}},
	{ name = "Ryo", combos = {
		{ 0, "cr.B, cr.B, cr.A, hcb+B:Hien Shippuu Kyaku" },
		{ 0, "cr.B, cr.C, qcf+A:Ko'ou Ken" },
		{ 1, "cr.C, qcf hcb+A:Ryuuko Ranbu" },
		{ 2, "cl.C, dp+C:Kohou, qcf hcb+A:Ryuuko Ranbu" },
	}},
	{ name = "Robert", combos = {
		{ 0, "cr.B, cr.B, dp+C:Ryuuga" },
		{ 0, "cl.D, f+B:Ryuu Hanshuu, dp+C:Ryuuga" },
		{ 1, "cr.B, cr.B, qcfx2+B:Haiga Ryuu" },
		{ 1, "cl.D, f+B:Ryuu Hanshuu, qcf hcb+C:Ryuuko Ranbu" },
		{ 2, "cl.D, f+B:Ryuu Hanshuu, dp+C:Ryuuga, qcf hcb+C:Ryuuko Ranbu" },
	}},
	{ name = "Takuma", combos = {
		{ 0, "cr.B, cr.A, hcb+B:Hien Shippuu Kyaku" },
		{ 0, "cr.B, f+B:Kawara Wari, hcb+D:Hien Shippuu Kyaku" },
		{ 0, "cl.C, hcb+B:Hien Shippuu Kyaku" },
		{ 1, "cr.B, cr.A, qcf hcb+A:Ryuuko Ranbu" },
		{ 1, "cr.B, f+B:Kawara Wari, qcf hcb+A:Ryuuko Ranbu" },
	}},
	{ name = "Leona", combos = {
		{ 0, "cr.B, cr.A, [2]8+C:Moon Slasher" },
		{ 1, "cr.B, cr.A, qcb hcf+B:Rebel Spark" },
	}},
	{ name = "Ralf", combos = {
		{ 0, "cl.C, hcf+B:Super Argentine Backbreaker" },
		{ 0, "cr.A, cr.A, hcf+D:Super Argentine Backbreaker" },
		{ 0, "cr.A, cr.A, [4]6+C:Gatling Attack" },
		{ 2, "cr.A, cr.A, [4]6+C:Gatling Attack, qcb hcf+B:Umanori Vulcan Punch" },
		{ 2, "cr.B, BC:MAX, cl.C, qcb hcf+B:Umanori Vulcan Punch" },
	}},
	{ name = "Clark", combos = {
		{ 0, "cl.C, hcf+B:Super Argentine Backbreaker, qcf+A:Flashing Elbow" },
		{ 0, "B, cr.A, hcf+B:Super Argentine Backbreaker, qcf+A:Flashing Elbow" },
		{ 0, "cl.C, f+B:Stomping, hcf+A:Mount Tackle, dd+A:Clark Lift, qcf+A:Flashing Elbow" },
		{ 1, "f+B:Stomping, hcbx2+A:Ultra Argentine Backbreaker" },
		{ 1, "cl.C, hcbx2+A:Ultra Argentine Backbreaker" },
		{ 2, "cl.C, BC:MAX, 66, cl.C, hcbx2+A:Ultra Argentine Backbreaker" },
	}},
	{ name = "Athena", combos = {
		{ 0, "cl.C, dp+A:Psycho Sword" },
		{ 0, "cl.C, qcb+A:Psycho Ball" },
		{ 1, "cl.C, hcbx2+A:Shining Crystal Bit" },
		{ 2, "cl.C, dp+C:Psycho Sword, hcbx2+A:Shining Crystal Bit" },
	}},
	{ name = "Kensou", combos = {
		{ 0, "cl.D, hcf+A:Ryuu Renga" },
		{ 1, "cr.B, cr.A, qcf hcb+D:Shinryuu" },
		{ 1, "cl.D, qcf hcb+D:Shinryuu" },
	}},
	{ name = "Chin", combos = {
		{ 0, "cl.D, qcb+A:Hyoutan Geki" },
		{ 0, "cl.C, f+A, qcb+A:Hyoutan Geki" },
	}},
	{ name = "Mai", combos = {
		{ 0, "cl.C, df+B:Koku'en no Mai, qcb+A:Ryuu Enbu" },
		{ 0, "cl.C, hcf+B:Hissatsu Shinobi Bachi" },
		{ 1, "cl.C, df+B:Koku'en no Mai, qcb hcf+B:Chou Hissatsu Shinobi Bachi" },
		{ 1, "f+B:Benitsuru no Mai, cr.C, qcb hcf+B:Chou Hissatsu Shinobi Bachi" },
	}},
	{ name = "Yuri", combos = {
		{ 0, "cr.B, cr.B, cr.A, dp+C:Yuri Chou Upper, dp+C:Double Upper" },
		{ 0, "cl.C, dp+C:Yuri Chou Upper, dp+C:Double Upper" },
		{ 1, "cl.C, df+B, qcf hcb+B:Hien Hou'ou Kyaku" },
		{ 2, "cr.B, cr.A, dp+C:Yuri Chou Upper, qcf hcb+B:Hien Hou'ou Kyaku" },
	}},
	{ name = "May Lee", combos = {
		{ 0, "cl.D, qcf+D:Tatsuo Kyaku, D:Kazeguruma, uf+D:Taiyou Kyaku, d+D:Rakuyou Kyaku" },
	}},
	{ name = "Chang", combos = {
		{ 0, "cr.A, cr.A, hcb f+A:Dai Hakai Nage" },
		{ 0, "cr.C, dd+B:Haki Kyaku" },
		{ 1, "cr.A, cr.A, qcfx2+A:Tekkyuu Dai Assatsu" },
		{ 2, "cr.C, dd+B:Haki Kyaku, qcfx2+B:Tekkyuu Dai Bokusatsu" },
	}},
	{ name = "Choi", combos = {
		{ 0, "cr.B, cr.B, A" },
		{ 1, "cr.B, cr.B, A, qcf hcb+B:Hou'ou Kyaku" },
		{ 1, "cr.C, qcf hcb+B:Hou'ou Kyaku" },
		{ 1, "f+B:Toorima Geri, A, qcf hcb+B:Hou'ou Kyaku" },
		{ 3, "cr.B, cr.B, BC:MAX, cr.C, qcf hcb+BD:Hou'ou Kyaku (SDM)" },
	}},
	{ name = "Iori", combos = {
		{ 0, "cl.C, qcb+A:Aoi Hana, qcb+A, qcb+A" },
		{ 0, "cl.C, hcb+B:Kototsuki In" },
		{ 1, "cl.C, f+A:Yumebiki, qcf hcb+A:Ya Otome" },
		{ 2, "cl.C, f+A:Yumebiki, qcf hcb+A:Ya Otome, qcfx4+AC:Saika" },
	}},
	{ name = "Mature", combos = {
		{ 0, "cl.B, qcb+C:Death Row, qcb+C, qcb+C" },
		{ 0, "cr.C, dp+C:Sacrilege" },
		{ 1, "cl.B, qcfx2+A:Nocturnal Rites" },
		{ 1, "cr.B, cr.B, cr.A, qcfx2+A:Nocturnal Rites" },
		{ 1, "cr.C, qcb hcf+B:Heaven's Gate" },
	}},
	{ name = "Vice", combos = {
		{ 0, "cl.D, f+A:Monstrosity, hcf+B:Decide" },
		{ 0, "cl.D, qcb+C:Mayhem, qcf+A:Mithan's Robe" },
		{ 0, "cr.B, hcb f+A:Gorefest" },
		{ 0, "cr.B, cr.B, cr.A, qcb+A:Mayhem, qcf+A:Mithan's Robe" },
		{ 1, "cl.D, hcbx2+B:Negative Gain" },
		{ 2, "f+A:Monstrosity, BC:MAX, 66, cl.D, hcbx2+B:Negative Gain" },
	}},
	{ name = "Billy", combos = {
		{ 0, "cl.D, hcf+A:Chuudan Uchi, qcf+A:Kaen" },
		{ 0, "cr.B, cr.B, dp+B:Kyoushuu Hishou Kon" },
		{ 1, "cr.B, cr.B, qcfx2+A:Dai Senpuu" },
		{ 2, "cl.D, BC:MAX, 66, cl.D, hcf+A:Chuudan Uchi, qcfx2+A:Dai Senpuu" },
	}},
	{ name = "Mary", combos = {
		{ 0, "cr.B, cr.B, dp+B:Vertical Arrow" },
		{ 0, "cl.C, f+A:Hammer Arch, [4]6+B:Straight Slicer" },
		{ 1, "cl.C, f+A:Hammer Arch, qcf hcb+A:Splash Rose" },
		{ 2, "cr.B, dp+B:Vertical Arrow, qcf hcb+A:Splash Rose" },
	}},
	{ name = "Yamazaki", combos = {
		{ 0, "cl.C, f+A:Bussashi, qcb+B:Hebi Tsukai" },
		{ 0, "cl.C, dp+D:Sunakake, qcb+B:Hebi Tsukai" },
		{ 0, "cr.B, cr.A, qcb+B:Hebi Tsukai" },
	}},
	{ name = "Chris", combos = {
		{ 0, "cr.B, cr.B, cr.B, B" },
		{ 0, "cr.C, f+A:Spinning Array, hcb+A:Shooting Dancer" },
		{ 1, "cl.C, f+A:Spinning Array, qcfx2+A:Chain Slide Touch" },
		{ 2, "cl.C, f+A:Spinning Array, hcb+A:Shooting Dancer, qcfx2+A:Chain Slide Touch" },
	}},
	{ name = "Shermie", combos = {
		{ 0, "cr.A, B, hcf+A:Shermie Spiral, qcf+B:Shermie Cute" },
		{ 0, "cr.C, f+B:Shermie Stand, hcf+A:Shermie Spiral, qcf+B:Shermie Cute" },
		{ 1, "cr.A, B, hcbx2+A:Shermie Flash" },
		{ 1, "cr.C, f+B:Shermie Stand, hcbx2+A:Shermie Flash" },
		{ 1, "cr.A, B, hcfx2+A:Shermie Carnival" },
	}},
	{ name = "Yashiro", combos = {
		{ 0, "cr.A, cr.A, A, B" },
		{ 0, "cl.C, f+A:Regret Bash, hcf+AC:Jet Counter, qcf+C:Still" },
		{ 1, "cr.B, cr.A, A, qcfx2+A:Final Impact" },
		{ 1, "cl.C, f+A:Regret Bash, hcf+AC:Jet Counter, qcf+C:Still, qcfx2+A:Final Impact" },
		{ 2, "hcf+C:Jet Counter, qcf+C:Still, qcfx2+A:Final Impact" },
	}},
	{ name = "K'", combos = {
		{ 0, "cl.C, f+A:An Inch, qcf+A:Iron Trigger, f+B:Second Shoot" },
		{ 0, "cr.B, cr.B, qcf+A:Iron Trigger, f+B:Second Shoot" },
		{ 1, "cl.C, f+A:An Inch, qcfx2+A:Heat Drive" },
		{ 1, "cl.C, f+A:An Inch, qcf hcb+A:Chain Drive" },
		{ 2, "cl.C, f+A:An Inch, dp+A:Crow Bites, qcfx2+A:Heat Drive" },
	}},
	{ name = "Maxima", combos = {
		{ 0, "cr.A, cr.A, df+C:Maxima Missile, qcb+A:Vapour Cannon" },
		{ 0, "cl.C, f+A:Mongolian, qcb+A:Vapour Cannon" },
		{ 0, "cr.A, cr.A, cr.A, qcf+A:Maxima Scramble, qcf+A:Double Bomber, qcf+A:Bulldog Press" },
		{ 1, "cl.C, f+A:Mongolian, hcbx2+B:Maxima Revenger" },
		{ 2, "cr.A, cr.A, qcf+A:Maxima Scramble, qcf+A:Double Bomber, qcf hcb+A:Bunker Buster" },
	}},
	{ name = "Whip", combos = {
		{ 0, "cl.B, cr.B, hcf+A:Boomerang Shot" },
		{ 0, "cl.D, f+A:Whip Shot, hcf+A:Boomerang Shot" },
		{ 1, "cl.B, cr.B, qcb hcf+A:Sonic Slaughter" },
	}},
	{ name = "Vanessa", combos = {
		{ 0, "cl.C, f+A, hcf+C:Machine Gun Puncher" },
		{ 1, "cl.C, f+A, qcb hcf+A:Crazy Puncher" },
	}},
	{ name = "Seth", combos = {
		{ 0, "cr.A, df+B:Sliding, qcf+A:Sho-Yoh" },
		{ 0, "cr.A, df+B:Sliding, hcb+B:Kyu-Getsu, f+B:Ya-Getsu" },
		{ 1, "cr.A, df+B:Sliding, qcfx2+A:Morote Sho-Yoh" },
		{ 1, "cl.D, b+A:Back Blow, qcfx2+A:Morote Sho-Yoh" },
		{ 2, "cl.D, b+A:Back Blow, qcf+A:Sho-Yoh, qcfx2+A:Morote Sho-Yoh" },
	}},
	{ name = "Ramon", combos = {
		{ 0, "cl.B, cr.A, hcf+A:Tiger Neck Chancery" },
		{ 0, "cl.C, df+B, hcf+B:Somersault" },
		{ 1, "cl.C, df+B, hcbx2+A:Tiger Spin" },
		{ 1, "cl.B, cr.A, hcbx2+A:Tiger Spin" },
	}},
	{ name = "Kula", combos = {
		{ 0, "cr.B, cr.B, B, dp+C:Crow Bites" },
		{ 0, "cl.C, qcb+B:Ray Spin, f+D:Sit, dp+C:Crow Bites" },
		{ 0, "cl.C, f+A:One Inch, qcb+B:Ray Spin, f+D:Sit, qcb+A:Counter Shell" },
		{ 2, "cr.B, cr.B, B, dp+C:Crow Bites, qcfx2+A:Diamond Edge" },
		{ 3, "cl.C, BC:MAX, 66, cl.C, f+A:One Inch, hcbx2+AC:Freeze Execution" },
	}},
	{ name = "K9999", combos = {
		{ 0, "cl.C, f+A:Urusee, qcf+A:Acchihe itteroo" },
		{ 0, "cr.B, cr.A, dp+A:Wareroo" },
	}},
	{ name = "Angel", combos = {
		{ 0, "cl.D, f+B, hcb+B:Red Sky of Yaponesia" },
		{ 0, "cr.B, B, rdp+B:Mad Murder Roulette, hcb+B:Red Sky of Yaponesia" },
		{ 1, "cl.D, f+B, b dp+A:Loyalty Test" },
	}},
	{ name = "Kusanagi", combos = {
		{ 0, "cr.B, cr.A, df+D:88 Shiki" },
		{ 0, "cl.C, hcb+B:Kototsuki You" },
		{ 0, "cl.C, f+B:Goufu You, qcf+A:Yami Barai" },
		{ 1, "cl.C, qcf+D:75 Shiki Kai, D, qcb hcf+C:Orochinagi" },
		{ 1, "cl.C, f+B:Goufu You, qcb hcf+C:Orochinagi" },
	}},
	{ name = "O.Yashiro", combos = {
		{ 0, "cl.C, f+A:Saku, hcb f+A:Musebu Daichi" },
		{ 0, "cr.B, cr.A, hcb f+A:Musebu Daichi" },
		{ 1, "cl.C, f+A:Saku, hcbx2+A:Ankoku Jigoku Gokuraku" },
		{ 3, "cl.D, f+A:Saku, BC:MAX, cl.D, f+A:Saku, hcbx2+AC:Ankoku Jigoku (SDM)" },
	}},
	{ name = "O.Shermie", combos = {
		{ 0, "cl.C, f+B:Kourai, hcf+B:Mugetsu Raiun" },
		{ 0, "cl.C, f+B:Kourai, qcb+A:Yatanagi no Muchi" },
		{ 1, "cl.C, f+B:Kourai, qcfx2+A:Ankoku Raikoken" },
		{ 1, "cr.C, qcfx2+B:Shukumei Gen'ei Shinshi" },
	}},
	{ name = "O.Chris", combos = {
		{ 0, "cl.C, f+A:Muyou no Ono, qcf+A:Taiyou wo Iru Honoo" },
		{ 0, "cr.B, cr.A, dp+A:Tsuki wo Tsumu Honoo" },
		{ 1, "cl.C, qcb hcf+A:Ankoku Orochinagi" },
	}},
}

----------------------------------------------------------------------------
-- Lectura de la notacion
----------------------------------------------------------------------------
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function parseButtons(s, spec)
	if spec == "P" then spec = "A/C" elseif spec == "K" then spec = "B/D" end
	s.b = spec
	s.any = spec:find("/") ~= nil
	s.btns, s.set = {}, {}
	for c in spec:gmatch("[ABCD]") do
		table.insert(s.btns, c)
		s.set[c] = true
	end
	if #s.btns == 0 then error("boton invalido: " .. spec) end
end

local function buildIcons(s)
	local icons = {}
	if s.ch then
		table.insert(icons, { dir = s.ch.icons[1], hold = true })
		table.insert(icons, { dir = s.ch.icons[2] })
	elseif s.m then
		for _, d in ipairs(MOTIONS[s.m]) do
			if d ~= 5 then table.insert(icons, { dir = d }) end
		end
	elseif s.dirIcon then
		table.insert(icons, { dir = s.dirIcon })
	end
	if s.btns then
		for i, b in ipairs(s.btns) do
			if i > 1 and s.any then table.insert(icons, { sep = "/" }) end
			table.insert(icons, { btn = b })
		end
	end
	s.icons = icons
end

local function parseStep(tok)
	local body, name = tok:match("^(.-):(.+)$")
	body = trim(body or tok)
	local s = { l = body, n = name and trim(name) or body }

	local pre, spec = body:match("^(.-)%+([ABCDPK/]+)$")
	if body == "66" then
		s.m = "ff"
	elseif pre then
		local key = pre:gsub("%s", "")
		if CHARGES[key] then
			s.ch = CHARGES[key]
		elseif DIRS[key] then
			s.d, s.dirIcon = DIRS[key], DIR_ICON[key]
		elseif MOTIONS[key] then
			s.m = key
		else
			error("movimiento desconocido: " .. pre)
		end
		parseButtons(s, spec)
	else
		local prefix, b = body:match("^(%a+)[%. ]([ABCD])$")
		if prefix == "cr" then
			s.d, s.dirIcon = DIRS.d, 2
			parseButtons(s, b)
		elseif prefix == "cl" or prefix == "st" or prefix == "far" then
			parseButtons(s, b)
		elseif body:match("^[ABCD]+$") then
			parseButtons(s, body)
		else
			error("paso desconocido: " .. body)
		end
	end
	buildIcons(s)
	return s
end

local function parseCombo(stock, text)
	local steps, names = {}, {}
	for tok in (text .. ","):gmatch("([^,]+),") do
		local s = parseStep(tok)
		table.insert(steps, s)
		if s.n ~= s.l then table.insert(names, s.n) end
	end
	local title = #names > 0 and table.concat(names, " > ") or text
	return { stock = stock, steps = steps, name = title, text = text }
end

for _, ch in ipairs(CHARS) do
	for _, listName in ipairs({ "combos", "rekkas" }) do
		if ch[listName] then
			local parsed = {}
			for _, c in ipairs(ch[listName]) do
				local ok, res = pcall(parseCombo, c[1], c[2])
				if ok then
					table.insert(parsed, res)
				else
					print("[" .. ch.name .. "] combo ignorado (" .. tostring(res) .. "): " .. c[2])
				end
			end
			ch[listName] = #parsed > 0 and parsed or nil
		end
	end
end

-- orden alfabetico en el menu de personajes
table.sort(CHARS, function(a, b) return a.name:lower() < b.name:lower() end)

----------------------------------------------------------------------------
-- Estado
----------------------------------------------------------------------------
local BUTTONS = { "A", "B", "C", "D" }
local frame = 0
local hist = {}        -- hist[frame] = direccion numpad
local held = {}        -- botones apretados el frame anterior
local lastPress = { A = -999, B = -999, C = -999, D = -999 }
local menuHeld = {}

local curChar = 1      -- personaje seleccionado
local cur = 1          -- combo seleccionado
local T                -- intento actual
local notice           -- { text, until } aviso temporal

local listMode = "combos" -- "combos" o "rekkas"

local function list() return CHARS[curChar][listMode] or CHARS[curChar].combos end
local function combo() return list()[cur] end
local function listLabel() return listMode == "rekkas" and " REKKA" or "" end

-- repeticiones logradas de cada combo en esta sesion (meta: REPS_GOAL)
local REPS_GOAL = 10
local reps = {}
local function repKey() return CHARS[curChar].name .. listMode .. cur end
local function repCount() return reps[repKey()] or 0 end
local function addRep()
	local k = repKey()
	if (reps[k] or 0) >= REPS_GOAL then reps[k] = 0 end -- ya completo: empieza otra tanda
	reps[k] = (reps[k] or 0) + 1
end

local function reset()
	T = {
		state = "ready",    -- ready | running | finished | result
		step = 1,
		everHit = false,
		pending = nil,      -- frame del primer boton de un "BC" incompleto
	}
	for _, b in ipairs(BUTTONS) do lastPress[b] = -999 end
end

local function selectCombo(delta)
	cur = (cur - 1 + delta) % #list() + 1
	reset()
end

local function selectChar(idx)
	curChar = (idx - 1) % #CHARS + 1
	if not CHARS[curChar][listMode] then listMode = "combos" end
	cur = 1
	reset()
end

local function charIndex(name)
	for i, ch in ipairs(CHARS) do
		if ch.name == name then return i end
	end
end

----------------------------------------------------------------------------
-- Deteccion del personaje
-- No hay una direccion publica con el ID del personaje en kof2002, asi que el
-- script la aprende: cada vez que completas un combo guarda una foto de la
-- memoria de P1. Con 3 personajes distintos busca el unico byte que vale lo
-- mismo para cada personaje y distinto entre ellos. Desde ahi detecta solo.
----------------------------------------------------------------------------
local SCAN_BASE, SCAN_LEN = 0x108100, 0x100
local DATA_FILE = "kof2002_combo_trials_datos.txt"
local learn = { addr = nil, ids = {}, snaps = {}, bad = {}, last = nil } -- snaps[nombre] = { {bytes}, ... }
local lastAutoId

-- inputs por frame -> texto compacto: "5*12,2B,6C#1,..." (#n = ahi se completa el paso n)
local function encodeFrames(frames)
	local out, prevTok, count = {}, nil, 0
	local function flush()
		if prevTok then out[#out + 1] = count > 1 and (prevTok .. "*" .. count) or prevTok end
	end
	for _, fr in ipairs(frames) do
		local tok = fr.dir .. fr.btns .. (fr.step and ("#" .. fr.step) or "")
		if tok == prevTok and not fr.step then
			count = count + 1
		else
			flush()
			prevTok, count = tok, 1
		end
	end
	flush()
	return table.concat(out, ",")
end

local function saveLearn()
	local f = io.open(DATA_FILE, "w")
	if not f then return end
	if learn.last then f:write("last " .. learn.last .. "\n") end
	if learn.addr then f:write(string.format("addr %X\n", learn.addr)) end
	for id, name in pairs(learn.ids) do f:write(string.format("id %d %s\n", id, name)) end
	for off in pairs(learn.bad) do f:write(string.format("bad %d\n", off)) end
	for name, list in pairs(learn.snaps) do
		for _, snap in ipairs(list) do
			local hex = {}
			for i = 1, SCAN_LEN do hex[i] = string.format("%02X", snap[i]) end
			f:write("snap " .. table.concat(hex) .. " " .. name .. "\n")
		end
	end
	f:close()
end

local function loadLearn()
	local f = io.open(DATA_FILE, "r")
	if not f then return end
	for line in f:lines() do
		local a = line:match("^addr (%x+)")
		local id, idName = line:match("^id (%d+) (.+)$")
		local hex, snapName = line:match("^snap (%x+) (.+)$")
		local bad = line:match("^bad (%d+)")
		local last = line:match("^last (.+)$")
		if a then learn.addr = tonumber(a, 16)
		elseif last then learn.last = last
		elseif bad then learn.bad[tonumber(bad)] = true
		elseif id then learn.ids[tonumber(id)] = idName
		elseif hex and #hex == SCAN_LEN * 2 then
			local snap = {}
			for i = 1, SCAN_LEN do snap[i] = tonumber(hex:sub(i * 2 - 1, i * 2), 16) end
			learn.snaps[snapName] = learn.snaps[snapName] or {}
			table.insert(learn.snaps[snapName], snap)
		end
	end
	f:close()
end

local function findCharAddr()
	local names = {}
	for name in pairs(learn.snaps) do table.insert(names, name) end
	if #names < 3 then return nil end
	local found
	for i = 1, SCAN_LEN do
		local seen, ok = {}, not learn.bad[i]
		for _, name in ipairs(names) do
			local v = learn.snaps[name][1][i]
			for _, snap in ipairs(learn.snaps[name]) do
				if snap[i] ~= v then ok = false end
			end
			if seen[v] then ok = false end
			seen[v] = true
		end
		if ok then
			if found then return nil end -- todavia hay mas de un candidato
			found = i
		end
	end
	return found
end

local function learnFromSuccess()
	local name = CHARS[curChar].name
	if learn.addr then
		local id = rb(learn.addr)
		if learn.ids[id] == nil then
			learn.ids[id] = name
			saveLearn()
			return
		elseif learn.ids[id] == name then
			return
		end
		-- dos personajes con el mismo valor: ese byte no era el ID, seguir buscando
		print(string.format("0x%X no era el ID del personaje, sigo buscando", learn.addr))
		learn.bad[learn.addr - SCAN_BASE + 1] = true
		learn.addr, learn.ids = nil, {}
	end
	local snap = {}
	for i = 1, SCAN_LEN do snap[i] = rb(SCAN_BASE + i - 1) end
	learn.snaps[name] = learn.snaps[name] or {}
	if #learn.snaps[name] >= 3 then table.remove(learn.snaps[name], 1) end
	table.insert(learn.snaps[name], snap)
	local off = findCharAddr()
	if off then
		learn.addr = SCAN_BASE + off - 1
		for n, list in pairs(learn.snaps) do learn.ids[list[1][off]] = n end
		print(string.format("Personaje detectado en 0x%X", learn.addr))
		notice = { text = "Ya reconozco a los personajes solo", untilFrame = frame + 180 }
	end
	saveLearn()
end

-- solo cambia cuando cambia el personaje en el juego, asi se puede elegir otro a mano
local function autoDetect()
	if not learn.addr or T.state ~= "ready" or frame % 30 ~= 0 then return end
	local id = rb(learn.addr)
	if id == lastAutoId then return end
	lastAutoId = id
	local idx = charIndex(learn.ids[id])
	if idx and idx ~= curChar then selectChar(idx) end
end

----------------------------------------------------------------------------
-- Lectura de inputs
----------------------------------------------------------------------------
local btnHist = {}    -- btnHist[frame] = botones apretados, ej. "BC"

-- Registro: cada intento se anota en un archivo para revisarlo
-- (pasos, golpes e inputs frame a frame).
local LOG_FILE = "kof2002_combo_trials_log.txt"
local hitsHist = {}   -- hitsHist[frame] = contador de golpes

local function logAttempt(kind, ok, msg, from, to)
	local f = io.open(LOG_FILE, "a")
	if not f then return end
	local stamp = (os and os.date) and os.date("%H:%M:%S") or ""
	f:write(string.format("[%s] %s %s%s %d/%d %s: %s\n", stamp, kind, CHARS[curChar].name, listLabel(), cur,
		#list(), ok and "OK" or "FALLO", msg or ""))
	f:write("  combo: " .. combo().text .. "\n")
	local marks = {}
	for i = 1, #combo().steps do
		local sf = T.stepFrames and T.stepFrames[i]
		if sf then marks[#marks + 1] = i .. "@" .. (sf - from) end
	end
	f:write("  pasos completados (paso@frame): " .. table.concat(marks, " ") .. "\n")
	local changes, last = {}, hitsHist[from]
	for fr = from, to do
		local h = hitsHist[fr]
		if h and h ~= last then changes[#changes + 1] = h .. "@" .. (fr - from); last = h end
	end
	f:write("  golpes (contador@frame): " .. table.concat(changes, " ") .. "\n")
	local frames = {}
	for fr = from, to do
		frames[#frames + 1] = { dir = hist[fr] or 5, btns = btnHist[fr] or "" }
	end
	f:write("  inputs: " .. encodeFrames(frames) .. "\n")
	f:close()
end

local function readDir(j)
	local facingLeft = rb(ADDR.p1_facing) == 0
	local f, b
	if facingLeft then f, b = j["P1 Left"], j["P1 Right"] else f, b = j["P1 Right"], j["P1 Left"] end
	local x = (f and 1 or 0) - (b and 1 or 0)
	local y = (j["P1 Up"] and 1 or 0) - (j["P1 Down"] and 1 or 0)
	return 5 + x + 3 * y
end

-- busca la secuencia (en orden) dentro de la ventana del movimiento,
-- sin ir mas atras de minFrame (el frame en que se apreto el paso anterior)
local function matchMotion(name, endFrame, minFrame)
	local seq, k = MOTIONS[name], #MOTIONS[name]
	for f = endFrame, math.max(endFrame - WINDOW[name], minFrame or -math.huge), -1 do
		if hist[f] == seq[k] then
			k = k - 1
			if k == 0 then return true end
		end
	end
	return false
end

-- direccion de carga mantenida CHARGE_FRAMES y luego la contraria hace poco
local function matchCharge(ch, endFrame)
	local f = endFrame
	while hist[f] and not ch.to(hist[f]) and f > endFrame - 10 do f = f - 1 end
	if not (hist[f] and ch.to(hist[f])) then return false end
	while hist[f] and ch.to(hist[f]) do f = f - 1 end
	local skip = 0
	while hist[f] and not ch.from(hist[f]) and skip < 3 do f, skip = f - 1, skip + 1 end
	local n = 0
	while hist[f] and ch.from(hist[f]) do f, n = f - 1, n + 1 end
	return n >= CHARGE_FRAMES
end

local function matchDir(dirs, endFrame)
	for f = endFrame, endFrame - 2, -1 do
		for _, d in ipairs(dirs) do
			if hist[f] == d then return true end
		end
	end
	return false
end

----------------------------------------------------------------------------
-- Logica del trial
----------------------------------------------------------------------------
-- step: paso cuyo input se dibuja junto al mensaje (opcional)
local function fail(msg, step)
	T.state, T.ok, T.msg, T.resultFrame = "result", false, msg, frame
	T.failedStep = T.step
	T.failIcons = step and step.icons
	pcall(logAttempt, "TRIAL", false, "paso " .. T.step .. ": " .. msg, (T.startFrame or frame) - 20, frame)
end

local function advance()
	local s = combo().steps[T.step]
	if s.btns then
		for _, b in ipairs(s.btns) do lastPress[b] = -999 end -- no reutilizar este boton
	end
	if T.state == "ready" then
		-- el contador puede venir con golpes del intento anterior: se cuenta desde aqui
		local hits = rb(ADDR.p1_hits)
		T.state, T.startFrame, T.baseHits, T.lastHits = "running", frame, hits, hits
		T.stepFrames = {}
	end
	T.stepFrames[T.step] = frame
	T.pending = nil
	T.step = T.step + 1
	if T.step > #combo().steps then
		T.state, T.finishFrame, T.hitsAtFinish = "finished", frame, rb(ADDR.p1_hits)
	end
end

-- devuelve nil si esta bien, o el motivo del error
local function prevStepFrame()
	return T.stepFrames and T.stepFrames[T.step - 1]
end

local function checkRequirements(s)
	if s.m and not matchMotion(s.m, frame, prevStepFrame()) then return "Movimiento mal hecho" end
	if s.ch and not matchCharge(s.ch, frame) then return "Falto cargar" end
	if s.d and not matchDir(s.d, frame) then return "Direccion incorrecta" end
	return nil
end

local function onPress(pressed)
	local steps = combo().steps
	local s = steps[T.step]

	-- un paso sin boton (correr) se completa si ya esta en el historial
	if s.m and not s.btns then
		if matchMotion(s.m, frame, prevStepFrame()) then
			advance()
			s = steps[T.step]
			if not s then return end
		elseif T.state == "ready" then
			return
		else
			return fail("Te falto esto", s)
		end
	end

	for b in pairs(pressed) do
		if not s.set[b] then
			if T.state == "ready" then return end -- antes de empezar se ignora
			return fail("Apretaste " .. b, s)
		end
	end

	if not s.any then
		for _, b in ipairs(s.btns) do
			if lastPress[b] < frame - SIMUL then
				T.pending = T.pending or frame
				return
			end
		end
	end

	local err = checkRequirements(s)
	if err then
		if T.state == "ready" then return end
		return fail(err, s)
	end
	advance()
end

local function updateTrial()
	local hits = rb(ADDR.p1_hits)
	memory.writeword(ADDR.timer, TIMER_FULL) -- tiempo infinito

	if T.state == "ready" then
		if hits == 0 then -- rellenar vida y barras entre intentos
			wb(ADDR.p2_health, P2_MAX_HEALTH)
			wb(ADDR.p1_stock, STOCK_FILL)
		end
		return
	end

	-- se reinicia rapido, sin esperar a que el rival se recupere
	if T.state == "result" then
		if frame - T.resultFrame > (T.ok and OK_FRAMES or FAIL_FRAMES) then reset() end
		return
	end

	if hits < T.lastHits and not T.everHit then T.baseHits = hits end -- termino el combo anterior
	if hits > T.baseHits then T.everHit = true end
	local dropped = T.everHit and hits < T.lastHits -- el contador bajo: el combo se corto
	T.lastHits = hits

	if T.pending and frame - T.pending > SIMUL then
		return fail("Aprieta a la vez", combo().steps[T.step])
	end

	if dropped then
		local s = combo().steps[T.step]
		return fail(s and "Se corto el combo aqui" or "Se corto el combo", s)
	end
	if not T.everHit and frame - T.startFrame > FIRST_HIT_MAX then
		return fail("El primer golpe no conecto")
	end

	if T.state == "finished" then
		if hits > T.hitsAtFinish then
			addRep()
			T.state, T.ok, T.msg, T.resultFrame = "result", true, "LOGRADO!", frame
			pcall(logAttempt, "TRIAL", true, "LOGRADO", T.startFrame - 20, frame)
			learnFromSuccess()
		elseif frame - T.finishFrame > LAST_HIT_MAX then
			T.step = #combo().steps
			fail("El ultimo golpe no conecto")
		end
	end
end

----------------------------------------------------------------------------
-- Menu (Start + direcciones / botones)
----------------------------------------------------------------------------
-- si "registers" existe, nos cargo fbneo-training-mode como addon
local AS_ADDON = type(registers) == "table" and registers.registerbefore ~= nil
local MODES = { "compact", "full", "hidden" }
local modeIdx = 1
local visible = true

local function handleMenu(j)
	-- en el training mode Coin abre su propio menu, asi que ahi solo usamos Start
	local mod = j["P1 Start"] or (not AS_ADDON and j["P1 Coin"])
	local now = {
		L = j["P1 Left"], R = j["P1 Right"], D = j["P1 Down"], U = j["P1 Up"],
		A = j["P1 Button A"], C = j["P1 Button C"], BD = j["P1 Button D"],
	}
	if mod then
		if now.R and not menuHeld.R then selectCombo(1) end
		if now.L and not menuHeld.L then selectCombo(-1) end
		if now.U and not menuHeld.U then selectChar(curChar - 1) end
		if now.D and not menuHeld.D then selectChar(curChar + 1) end
		if (now.U and not menuHeld.U) or (now.D and not menuHeld.D) then
			if learn.addr then lastAutoId = rb(learn.addr) end
			learn.last = CHARS[curChar].name -- recordar para la proxima vez
			saveLearn()
		end
		if now.BD and not menuHeld.BD then reset() end
		if now.A and not menuHeld.A and CHARS[curChar].rekkas then
			listMode = listMode == "combos" and "rekkas" or "combos"
			cur = 1
			reset()
		end
		if now.C and not menuHeld.C then
			modeIdx = modeIdx % #MODES + 1
			visible = MODES[modeIdx] ~= "hidden"
			reset()
		end
	end
	menuHeld = now
	return mod
end

-- los hotkeys 1-4 ya los usa el training mode
if not AS_ADDON and input and input.registerhotkey then
	input.registerhotkey(1, function() selectCombo(1) end)
	input.registerhotkey(2, function() selectCombo(-1) end)
	input.registerhotkey(3, function() selectChar(curChar + 1) end)
	input.registerhotkey(4, function() reset() end)
end

----------------------------------------------------------------------------
-- Dibujo
----------------------------------------------------------------------------
local COL = {
	bg      = 0x000000B0,
	border  = 0xFFFFFF60,
	title   = 0x80C0FFFF,
	done    = 0x40FF40FF,
	current = 0xFFFF40FF,
	pending = 0xFFFFFFFF,
	failed  = 0xFF4040FF,
	dim     = 0xA0A0A0FF,
}

local BTN_COL = { A = 0xE03030FF, B = 0xE0C020FF, C = 0x30B040FF, D = 0x3070E0FF }
local ICON, ROW_H = 10, 12

-- flecha de palanca (numpad) centrada en cx,cy; se espeja si P1 mira a la izquierda
local function drawArrow(cx, cy, dir, col, mirror)
	local vx = (dir - 1) % 3 - 1
	local vy = math.floor((dir - 1) / 3) - 1
	if mirror then vx = -vx end
	vy = -vy -- en pantalla "arriba" es y negativa
	local len = (vx ~= 0 and vy ~= 0) and 3 or 4
	local tx, ty = cx + vx * len, cy + vy * len
	local bx, by = cx - vx * len, cy - vy * len
	gui.line(bx, by, tx, ty, col)
	-- punta: dos alas hacia atras a +-45 grados
	local w = (vx ~= 0 and vy ~= 0) and 3 or 2
	local px, py = -vy, vx
	gui.line(tx, ty, tx - vx * w + px * w, ty - vy * w + py * w, col)
	gui.line(tx, ty, tx - vx * w - px * w, ty - vy * w - py * w, col)
	-- grosor extra
	if vx == 0 then gui.line(bx + 1, by, tx + 1, ty, col)
	elseif vy == 0 then gui.line(bx, by + 1, tx, ty + 1, col)
	else gui.line(bx + 1, by, tx + 1, ty, col) end
end

local function drawButton(x, y, b)
	local c = BTN_COL[b]
	gui.box(x + 1, y, x + ICON - 2, y + ICON - 1, c, c)
	gui.box(x, y + 1, x + ICON - 1, y + ICON - 2, c, c)
	gui.text(x + 3, y + 2, b, 0xFFFFFFFF)
end

local function drawIcons(x, y, icons, col, mirror)
	for _, ic in ipairs(icons) do
		if ic.dir then
			if ic.hold then gui.box(x - 1, y - 1, x + ICON - 1, y + ICON - 1, 0, col) end
			drawArrow(x + 4, y + 4, ic.dir, col, mirror)
			x = x + ICON + (ic.hold and 2 or 0)
		elseif ic.btn then
			drawButton(x, y, ic.btn)
			x = x + ICON
		elseif ic.sep then
			gui.text(x + 1, y + 2, ic.sep, col)
			x = x + 6
		end
	end
end

local function iconsWidth(icons)
	local w = 0
	for _, ic in ipairs(icons) do
		if ic.sep then w = w + 6 else w = w + ICON + (ic.hold and 2 or 0) end
	end
	return w
end

local function stepColor(i)
	if T.state == "result" and not T.ok and i == T.failedStep then return COL.failed
	elseif i < T.step or (T.state == "result" and T.ok) then return COL.done
	elseif i == T.step and T.state ~= "result" then return COL.current end
	return COL.pending
end

local function drawResult(x, y, mirror)
	if T.state ~= "result" then return end
	local col = T.ok and COL.done or COL.failed
	if T.failIcons then
		drawIcons(x, y - 2, T.failIcons, col, mirror)
		x = x + iconsWidth(T.failIcons) + 4
	end
	gui.text(x, y, T.msg, col)
end

local function drawNotice(x, y)
	if notice and frame < notice.untilFrame then gui.text(x, y, notice.text, COL.title) end
end

-- barra con todo el combo, centrada arriba; si no cabe en el ancho, sigue en otra linea
local function drawCompact()
	local c = combo()
	local label = string.format("%s%s %d/%d   x%d/%d", CHARS[curChar].name, listLabel(), cur, #list(),
		repCount(), REPS_GOAL)
	local GAP, ROW_GAP = 5, 4
	local screenW = emu.screenwidth and emu.screenwidth() or 304
	local maxW = screenW - 24

	-- repartir los pasos en lineas
	local rows, row, rowW = {}, {}, 0
	for i, s in ipairs(c.steps) do
		local sw = iconsWidth(s.icons)
		if #row > 0 and rowW + sw > maxW then
			rows[#rows + 1] = { steps = row, w = rowW - GAP }
			row, rowW = {}, 0
		end
		row[#row + 1] = i
		rowW = rowW + sw + GAP
	end
	rows[#rows + 1] = { steps = row, w = rowW - GAP }

	local mirror = rb(ADDR.p1_facing) == 0
	local y = 80
	local left = math.floor(screenW / 2 - rows[1].w / 2)
	-- nombre y numero arriba de la barra, asi no depende del ancho de la letra
	gui.text(left, y - 9, label, COL.title)
	for r, rw in ipairs(rows) do
		local x = math.floor(screenW / 2 - rw.w / 2)
		gui.box(x - 2, y - 2, x + rw.w + 2, y + ICON + 1, 0x00000080, 0)
		for k, i in ipairs(rw.steps) do
			local s = c.steps[i]
			local col = stepColor(i)
			local sw = iconsWidth(s.icons)
			drawIcons(x, y, s.icons, col, mirror)
			if col == COL.current or col == COL.failed then
				gui.line(x, y + ICON + 1, x + sw - 2, y + ICON + 1, col)
			end
			if i < #c.steps then gui.box(x + sw + 1, y + 4, x + sw + 2, y + 5, COL.dim, COL.dim) end
			x = x + sw + GAP
		end
		if r < #rows then y = y + ICON + ROW_GAP + 2 end
	end

	-- al fallar basta el paso en rojo; al lograrlo se muestra el texto
	if T.state == "result" and T.ok then
		local done = repCount() >= REPS_GOAL
		gui.text(left, y + ICON + 4, done and string.format("LOGRADO! %d/%d COMPLETO", REPS_GOAL, REPS_GOAL)
			or string.format("LOGRADO! %d/%d", repCount(), REPS_GOAL), COL.done)
	end
	drawNotice(left, y + ICON + 12)
end

local function draw()
	if not visible then return end
	if MODES[modeIdx] == "compact" then return drawCompact() end
	local c = combo()
	local mirror = rb(ADDR.p1_facing) == 0
	local x, y = 8, 36
	local h = 34 + #c.steps * ROW_H
	gui.box(x - 3, y - 3, x + 230, y + h, COL.bg, COL.border)

	gui.text(x, y, string.format("%s  %s %d/%d  (barras: %d)  BETA", CHARS[curChar].name:upper(),
		listMode == "rekkas" and "REKKA" or "COMBO", cur, #list(), c.stock), COL.title)
	gui.text(x + 170, y, string.format("x%d/%d", repCount(), REPS_GOAL), repCount() >= REPS_GOAL and COL.done or COL.title)
	gui.text(x, y + 9, c.name:sub(1, 56), COL.pending)

	for i, s in ipairs(c.steps) do
		local col = stepColor(i)
		local ry = y + 8 + i * ROW_H
		if col ~= COL.pending then gui.box(x - 2, ry - 2, x + 228, ry + ROW_H - 3, (col - 0xFF) + 0x30, 0) end
		local mark = (i < T.step) and "+" or (i == T.step and ">" or " ")
		gui.text(x, ry + 2, string.format("%s%d", mark, i), col)
		drawIcons(x + 14, ry, s.icons, col, mirror)
		gui.text(x + 128, ry + 2, s.n, col)
	end

	local fy = y + h - 10
	if T.state == "result" then
		drawResult(x, fy, mirror)
	elseif T.state == "ready" then
		gui.text(x, fy, "Start+flechas: personaje/combo  Start+C: modo", COL.dim)
	end
	drawNotice(x, y + h + 4)
end

----------------------------------------------------------------------------
-- Bucle principal
----------------------------------------------------------------------------
local rom = emu.romname and emu.romname() or "?"
if not rom:find("kof2002") and not rom:find("kf2k2") then
	print("Aviso: este script es para kof2002, ROM actual: " .. rom)
end
pcall(loadLearn)
if learn.last and charIndex(learn.last) then curChar = charIndex(learn.last) end
print(string.format("KOF 2002 Combo Trials (BETA) cargado: %d personajes.", #CHARS))

local function tick()
	frame = frame + 1
	local j = joypad.get()
	hist[frame] = readDir(j)
	hist[frame - HISTORY] = nil
	hitsHist[frame], hitsHist[frame - HISTORY] = rb(ADDR.p1_hits), nil

	local menu = handleMenu(j)
	local pressed, any, downNow = {}, false, ""
	for _, b in ipairs(BUTTONS) do
		local down = j["P1 Button " .. b]
		if down and not held[b] then
			pressed[b], any = true, true
			lastPress[b] = frame
		end
		if down then downNow = downNow .. b end
		held[b] = down
	end
	btnHist[frame] = downNow
	btnHist[frame - HISTORY] = nil

	if not visible then return end -- oculto: no tocar nada del juego
	autoDetect()
	-- un paso sin boton (correr) se marca apenas se hace, aunque el golpe venga despues
	local cs = combo().steps[T.step]
	if T.state == "running" and cs and cs.m and not cs.btns and matchMotion(cs.m, frame, prevStepFrame()) then advance() end
	if not menu and any and T.state ~= "result" and T.state ~= "finished" then
		onPress(pressed)
	end
	updateTrial()
end

reset()
if AS_ADDON then
	table.insert(registers.registerbefore, tick)
	table.insert(registers.guiregister, draw)
else
	gui.register(draw)
	while true do
		tick()
		emu.frameadvance()
	end
end
