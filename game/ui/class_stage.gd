class_name ClassStage
extends RefCounted
## The classes as the screens show them: their order, their colour and their signature move. The multiplayer page's
## class tiles and its 3D preview (MpLobbyView, TitleStage), the run's results and the lobby's class list read these.
## (The New Character screen's 3D carousel these came from is archived with Enter World: archive/camp/.)

## the classes, in order; the three dragons are spread through it (never two side by side)
const CLASSES := ["archer", "wyrm", "wraith", "knight", "doug", "serpent", "plague", "demon", "wyvern", "warlock", "necromancer"]
const ACCENTS := {"knight": Color(0.95, 0.72, 0.35), "wraith": Color(0.4, 0.85, 1.0), "demon": Color(1.0, 0.38, 0.1), "warlock": Color(0.45, 1.0, 0.35), "archer": Color(0.92, 0.24, 0.3), "plague": Color(0.6, 0.95, 0.3),
	"doug": Color(1.0, 0.82, 0.2), "wyrm": Color(1.0, 0.3, 0.12), "serpent": Color(0.55, 0.88, 1.0), "wyvern": Color(0.45, 0.95, 0.85),
	"necromancer": Color(0.45, 1.0, 0.6)}
## signature moves (the preview's hero does it once when hovered, TitleStage): [pose style, seconds, impact fraction, skill name]
const SIGNATURE := {"knight": ["cleave", 1.1, 0.5, "Holy Slam"], "wraith": ["rend", 0.95, 0.42, "Spectral Rend"],
	"demon": ["fists", 0.9, 0.48, "Molten Fists"], "warlock": ["cast", 2.0, 0.55, "Eclipse Bloom"], "archer": ["bow", 1.0, 0.55, "Volley"],
	"plague": ["pd_flask", 1.3, 0.55, "Pestilence Vial"], "doug": ["pie", 0.9, 0.5, "Cream Pie"],
	"necromancer": ["grave_slam", 1.3, 0.55, "Graveyard"],
	"wyrm": ["swipe3", 1.2, 0.47, "Tail Spin"], "serpent": ["swipe3", 1.1, 0.47, "Tail Spin"], "wyvern": ["swipe3", 1.1, 0.47, "Tail Spin"]}
