package ui

import "core:math"
import "core:strings"
import "core:unicode/utf8"
import rl "vendor:raylib"

// Embedded Font Awesome 6 Solid TrueType font binary (zero external file dependencies)
FA_SOLID_TTF :: #load("fonts/fa-solid-900.ttf")

DEFAULT_ICON_SIZE: f32 : 18.0

// ============================================================================
// Font Awesome 6 Solid Icon Enumeration (Backed by rune codepoints)
// ============================================================================
Icon :: enum rune {
	None = 0,
	Digit0 = 0x30, // fa-0
	Digit1 = 0x31, // fa-1
	Digit2 = 0x32, // fa-2
	Digit3 = 0x33, // fa-3
	Digit4 = 0x34, // fa-4
	Digit5 = 0x35, // fa-5
	Digit6 = 0x36, // fa-6
	Digit7 = 0x37, // fa-7
	Digit8 = 0x38, // fa-8
	Digit9 = 0x39, // fa-9
	A = 0x41, // fa-a
	AddressBook = 0xF2B9, // fa-address-book
	AddressCard = 0xF2BB, // fa-address-card
	AlignCenter = 0xF037, // fa-align-center
	AlignJustify = 0xF039, // fa-align-justify
	AlignLeft = 0xF036, // fa-align-left
	AlignRight = 0xF038, // fa-align-right
	Anchor = 0xF13D, // fa-anchor
	AnchorCircleCheck = 0xE4AA, // fa-anchor-circle-check
	AnchorCircleExclamation = 0xE4AB, // fa-anchor-circle-exclamation
	AnchorCircleXmark = 0xE4AC, // fa-anchor-circle-xmark
	AnchorLock = 0xE4AD, // fa-anchor-lock
	AngleDown = 0xF107, // fa-angle-down
	AngleLeft = 0xF104, // fa-angle-left
	AngleRight = 0xF105, // fa-angle-right
	AngleUp = 0xF106, // fa-angle-up
	AnglesDown = 0xF103, // fa-angles-down
	AnglesLeft = 0xF100, // fa-angles-left
	AnglesRight = 0xF101, // fa-angles-right
	AnglesUp = 0xF102, // fa-angles-up
	Ankh = 0xF644, // fa-ankh
	AppleWhole = 0xF5D1, // fa-apple-whole
	Archway = 0xF557, // fa-archway
	ArrowDown = 0xF063, // fa-arrow-down
	ArrowDown19 = 0xF162, // fa-arrow-down-1-9
	ArrowDown91 = 0xF886, // fa-arrow-down-9-1
	ArrowDownAZ = 0xF15D, // fa-arrow-down-a-z
	ArrowDownLong = 0xF175, // fa-arrow-down-long
	ArrowDownShortWide = 0xF884, // fa-arrow-down-short-wide
	ArrowDownUpAcrossLine = 0xE4AF, // fa-arrow-down-up-across-line
	ArrowDownUpLock = 0xE4B0, // fa-arrow-down-up-lock
	ArrowDownWideShort = 0xF160, // fa-arrow-down-wide-short
	ArrowDownZA = 0xF881, // fa-arrow-down-z-a
	ArrowLeft = 0xF060, // fa-arrow-left
	ArrowLeftLong = 0xF177, // fa-arrow-left-long
	ArrowPointer = 0xF245, // fa-arrow-pointer
	ArrowRight = 0xF061, // fa-arrow-right
	ArrowRightArrowLeft = 0xF0EC, // fa-arrow-right-arrow-left
	ArrowRightFromBracket = 0xF08B, // fa-arrow-right-from-bracket
	ArrowRightLong = 0xF178, // fa-arrow-right-long
	ArrowRightToBracket = 0xF090, // fa-arrow-right-to-bracket
	ArrowRightToCity = 0xE4B3, // fa-arrow-right-to-city
	ArrowRotateLeft = 0xF0E2, // fa-arrow-rotate-left
	ArrowRotateRight = 0xF01E, // fa-arrow-rotate-right
	ArrowTrendDown = 0xE097, // fa-arrow-trend-down
	ArrowTrendUp = 0xE098, // fa-arrow-trend-up
	ArrowTurnDown = 0xF149, // fa-arrow-turn-down
	ArrowTurnUp = 0xF148, // fa-arrow-turn-up
	ArrowUp = 0xF062, // fa-arrow-up
	ArrowUp19 = 0xF163, // fa-arrow-up-1-9
	ArrowUp91 = 0xF887, // fa-arrow-up-9-1
	ArrowUpAZ = 0xF15E, // fa-arrow-up-a-z
	ArrowUpFromBracket = 0xE09A, // fa-arrow-up-from-bracket
	ArrowUpFromGroundWater = 0xE4B5, // fa-arrow-up-from-ground-water
	ArrowUpFromWaterPump = 0xE4B6, // fa-arrow-up-from-water-pump
	ArrowUpLong = 0xF176, // fa-arrow-up-long
	ArrowUpRightDots = 0xE4B7, // fa-arrow-up-right-dots
	ArrowUpRightFromSquare = 0xF08E, // fa-arrow-up-right-from-square
	ArrowUpShortWide = 0xF885, // fa-arrow-up-short-wide
	ArrowUpWideShort = 0xF161, // fa-arrow-up-wide-short
	ArrowUpZA = 0xF882, // fa-arrow-up-z-a
	ArrowsDownToLine = 0xE4B8, // fa-arrows-down-to-line
	ArrowsDownToPeople = 0xE4B9, // fa-arrows-down-to-people
	ArrowsLeftRight = 0xF07E, // fa-arrows-left-right
	ArrowsLeftRightToLine = 0xE4BA, // fa-arrows-left-right-to-line
	ArrowsRotate = 0xF021, // fa-arrows-rotate
	ArrowsSpin = 0xE4BB, // fa-arrows-spin
	ArrowsSplitUpAndLeft = 0xE4BC, // fa-arrows-split-up-and-left
	ArrowsToCircle = 0xE4BD, // fa-arrows-to-circle
	ArrowsToDot = 0xE4BE, // fa-arrows-to-dot
	ArrowsToEye = 0xE4BF, // fa-arrows-to-eye
	ArrowsTurnRight = 0xE4C0, // fa-arrows-turn-right
	ArrowsTurnToDots = 0xE4C1, // fa-arrows-turn-to-dots
	ArrowsUpDown = 0xF07D, // fa-arrows-up-down
	ArrowsUpDownLeftRight = 0xF047, // fa-arrows-up-down-left-right
	ArrowsUpToLine = 0xE4C2, // fa-arrows-up-to-line
	Asterisk = 0x2A, // fa-asterisk
	At = 0x40, // fa-at
	Atom = 0xF5D2, // fa-atom
	AudioDescription = 0xF29E, // fa-audio-description
	AustralSign = 0xE0A9, // fa-austral-sign
	Award = 0xF559, // fa-award
	B = 0x42, // fa-b
	Baby = 0xF77C, // fa-baby
	BabyCarriage = 0xF77D, // fa-baby-carriage
	Backward = 0xF04A, // fa-backward
	BackwardFast = 0xF049, // fa-backward-fast
	BackwardStep = 0xF048, // fa-backward-step
	Bacon = 0xF7E5, // fa-bacon
	Bacteria = 0xE059, // fa-bacteria
	Bacterium = 0xE05A, // fa-bacterium
	BagShopping = 0xF290, // fa-bag-shopping
	Bahai = 0xF666, // fa-bahai
	BahtSign = 0xE0AC, // fa-baht-sign
	Ban = 0xF05E, // fa-ban
	BanSmoking = 0xF54D, // fa-ban-smoking
	Bandage = 0xF462, // fa-bandage
	BangladeshiTakaSign = 0xE2E6, // fa-bangladeshi-taka-sign
	Barcode = 0xF02A, // fa-barcode
	Bars = 0xF0C9, // fa-bars
	BarsProgress = 0xF828, // fa-bars-progress
	BarsStaggered = 0xF550, // fa-bars-staggered
	Baseball = 0xF433, // fa-baseball
	BaseballBatBall = 0xF432, // fa-baseball-bat-ball
	BasketShopping = 0xF291, // fa-basket-shopping
	Basketball = 0xF434, // fa-basketball
	Bath = 0xF2CD, // fa-bath
	BatteryEmpty = 0xF244, // fa-battery-empty
	BatteryFull = 0xF240, // fa-battery-full
	BatteryHalf = 0xF242, // fa-battery-half
	BatteryQuarter = 0xF243, // fa-battery-quarter
	BatteryThreeQuarters = 0xF241, // fa-battery-three-quarters
	Bed = 0xF236, // fa-bed
	BedPulse = 0xF487, // fa-bed-pulse
	BeerMugEmpty = 0xF0FC, // fa-beer-mug-empty
	Bell = 0xF0F3, // fa-bell
	BellConcierge = 0xF562, // fa-bell-concierge
	BellSlash = 0xF1F6, // fa-bell-slash
	BezierCurve = 0xF55B, // fa-bezier-curve
	Bicycle = 0xF206, // fa-bicycle
	Binoculars = 0xF1E5, // fa-binoculars
	Biohazard = 0xF780, // fa-biohazard
	BitcoinSign = 0xE0B4, // fa-bitcoin-sign
	Blender = 0xF517, // fa-blender
	BlenderPhone = 0xF6B6, // fa-blender-phone
	Blog = 0xF781, // fa-blog
	Bold = 0xF032, // fa-bold
	Bolt = 0xF0E7, // fa-bolt
	BoltLightning = 0xE0B7, // fa-bolt-lightning
	Bomb = 0xF1E2, // fa-bomb
	Bone = 0xF5D7, // fa-bone
	Bong = 0xF55C, // fa-bong
	Book = 0xF02D, // fa-book
	BookAtlas = 0xF558, // fa-book-atlas
	BookBible = 0xF647, // fa-book-bible
	BookBookmark = 0xE0BB, // fa-book-bookmark
	BookJournalWhills = 0xF66A, // fa-book-journal-whills
	BookMedical = 0xF7E6, // fa-book-medical
	BookOpen = 0xF518, // fa-book-open
	BookOpenReader = 0xF5DA, // fa-book-open-reader
	BookQuran = 0xF687, // fa-book-quran
	BookSkull = 0xF6B7, // fa-book-skull
	BookTanakh = 0xF827, // fa-book-tanakh
	Bookmark = 0xF02E, // fa-bookmark
	BorderAll = 0xF84C, // fa-border-all
	BorderNone = 0xF850, // fa-border-none
	BorderTopLeft = 0xF853, // fa-border-top-left
	BoreHole = 0xE4C3, // fa-bore-hole
	BottleDroplet = 0xE4C4, // fa-bottle-droplet
	BottleWater = 0xE4C5, // fa-bottle-water
	BowlFood = 0xE4C6, // fa-bowl-food
	BowlRice = 0xE2EB, // fa-bowl-rice
	BowlingBall = 0xF436, // fa-bowling-ball
	Box = 0xF466, // fa-box
	BoxArchive = 0xF187, // fa-box-archive
	BoxOpen = 0xF49E, // fa-box-open
	BoxTissue = 0xE05B, // fa-box-tissue
	BoxesPacking = 0xE4C7, // fa-boxes-packing
	BoxesStacked = 0xF468, // fa-boxes-stacked
	Braille = 0xF2A1, // fa-braille
	Brain = 0xF5DC, // fa-brain
	BrazilianRealSign = 0xE46C, // fa-brazilian-real-sign
	BreadSlice = 0xF7EC, // fa-bread-slice
	Bridge = 0xE4C8, // fa-bridge
	BridgeCircleCheck = 0xE4C9, // fa-bridge-circle-check
	BridgeCircleExclamation = 0xE4CA, // fa-bridge-circle-exclamation
	BridgeCircleXmark = 0xE4CB, // fa-bridge-circle-xmark
	BridgeLock = 0xE4CC, // fa-bridge-lock
	BridgeWater = 0xE4CE, // fa-bridge-water
	Briefcase = 0xF0B1, // fa-briefcase
	BriefcaseMedical = 0xF469, // fa-briefcase-medical
	Broom = 0xF51A, // fa-broom
	BroomBall = 0xF458, // fa-broom-ball
	Brush = 0xF55D, // fa-brush
	Bucket = 0xE4CF, // fa-bucket
	Bug = 0xF188, // fa-bug
	BugSlash = 0xE490, // fa-bug-slash
	Bugs = 0xE4D0, // fa-bugs
	Building = 0xF1AD, // fa-building
	BuildingCircleArrowRight = 0xE4D1, // fa-building-circle-arrow-right
	BuildingCircleCheck = 0xE4D2, // fa-building-circle-check
	BuildingCircleExclamation = 0xE4D3, // fa-building-circle-exclamation
	BuildingCircleXmark = 0xE4D4, // fa-building-circle-xmark
	BuildingColumns = 0xF19C, // fa-building-columns
	BuildingFlag = 0xE4D5, // fa-building-flag
	BuildingLock = 0xE4D6, // fa-building-lock
	BuildingNgo = 0xE4D7, // fa-building-ngo
	BuildingShield = 0xE4D8, // fa-building-shield
	BuildingUn = 0xE4D9, // fa-building-un
	BuildingUser = 0xE4DA, // fa-building-user
	BuildingWheat = 0xE4DB, // fa-building-wheat
	Bullhorn = 0xF0A1, // fa-bullhorn
	Bullseye = 0xF140, // fa-bullseye
	Burger = 0xF805, // fa-burger
	Burst = 0xE4DC, // fa-burst
	Bus = 0xF207, // fa-bus
	BusSimple = 0xF55E, // fa-bus-simple
	BusinessTime = 0xF64A, // fa-business-time
	C = 0x43, // fa-c
	CableCar = 0xF7DA, // fa-cable-car
	CakeCandles = 0xF1FD, // fa-cake-candles
	Calculator = 0xF1EC, // fa-calculator
	Calendar = 0xF133, // fa-calendar
	CalendarCheck = 0xF274, // fa-calendar-check
	CalendarDay = 0xF783, // fa-calendar-day
	CalendarDays = 0xF073, // fa-calendar-days
	CalendarMinus = 0xF272, // fa-calendar-minus
	CalendarPlus = 0xF271, // fa-calendar-plus
	CalendarWeek = 0xF784, // fa-calendar-week
	CalendarXmark = 0xF273, // fa-calendar-xmark
	Camera = 0xF030, // fa-camera
	CameraRetro = 0xF083, // fa-camera-retro
	CameraRotate = 0xE0D8, // fa-camera-rotate
	Campground = 0xF6BB, // fa-campground
	CandyCane = 0xF786, // fa-candy-cane
	Cannabis = 0xF55F, // fa-cannabis
	Capsules = 0xF46B, // fa-capsules
	Car = 0xF1B9, // fa-car
	CarBattery = 0xF5DF, // fa-car-battery
	CarBurst = 0xF5E1, // fa-car-burst
	CarOn = 0xE4DD, // fa-car-on
	CarRear = 0xF5DE, // fa-car-rear
	CarSide = 0xF5E4, // fa-car-side
	CarTunnel = 0xE4DE, // fa-car-tunnel
	Caravan = 0xF8FF, // fa-caravan
	CaretDown = 0xF0D7, // fa-caret-down
	CaretLeft = 0xF0D9, // fa-caret-left
	CaretRight = 0xF0DA, // fa-caret-right
	CaretUp = 0xF0D8, // fa-caret-up
	Carrot = 0xF787, // fa-carrot
	CartArrowDown = 0xF218, // fa-cart-arrow-down
	CartFlatbed = 0xF474, // fa-cart-flatbed
	CartFlatbedSuitcase = 0xF59D, // fa-cart-flatbed-suitcase
	CartPlus = 0xF217, // fa-cart-plus
	CartShopping = 0xF07A, // fa-cart-shopping
	CashRegister = 0xF788, // fa-cash-register
	Cat = 0xF6BE, // fa-cat
	CediSign = 0xE0DF, // fa-cedi-sign
	CentSign = 0xE3F5, // fa-cent-sign
	Certificate = 0xF0A3, // fa-certificate
	Chair = 0xF6C0, // fa-chair
	Chalkboard = 0xF51B, // fa-chalkboard
	ChalkboardUser = 0xF51C, // fa-chalkboard-user
	ChampagneGlasses = 0xF79F, // fa-champagne-glasses
	ChargingStation = 0xF5E7, // fa-charging-station
	ChartArea = 0xF1FE, // fa-chart-area
	ChartBar = 0xF080, // fa-chart-bar
	ChartColumn = 0xE0E3, // fa-chart-column
	ChartDiagram = 0xE695, // fa-chart-diagram
	ChartGantt = 0xE0E4, // fa-chart-gantt
	ChartLine = 0xF201, // fa-chart-line
	ChartPie = 0xF200, // fa-chart-pie
	ChartSimple = 0xE473, // fa-chart-simple
	Check = 0xF00C, // fa-check
	CheckDouble = 0xF560, // fa-check-double
	CheckToSlot = 0xF772, // fa-check-to-slot
	Cheese = 0xF7EF, // fa-cheese
	Chess = 0xF439, // fa-chess
	ChessBishop = 0xF43A, // fa-chess-bishop
	ChessBoard = 0xF43C, // fa-chess-board
	ChessKing = 0xF43F, // fa-chess-king
	ChessKnight = 0xF441, // fa-chess-knight
	ChessPawn = 0xF443, // fa-chess-pawn
	ChessQueen = 0xF445, // fa-chess-queen
	ChessRook = 0xF447, // fa-chess-rook
	ChevronDown = 0xF078, // fa-chevron-down
	ChevronLeft = 0xF053, // fa-chevron-left
	ChevronRight = 0xF054, // fa-chevron-right
	ChevronUp = 0xF077, // fa-chevron-up
	Child = 0xF1AE, // fa-child
	ChildCombatant = 0xE4E0, // fa-child-combatant
	ChildDress = 0xE59C, // fa-child-dress
	ChildReaching = 0xE59D, // fa-child-reaching
	Children = 0xE4E1, // fa-children
	Church = 0xF51D, // fa-church
	Circle = 0xF111, // fa-circle
	CircleArrowDown = 0xF0AB, // fa-circle-arrow-down
	CircleArrowLeft = 0xF0A8, // fa-circle-arrow-left
	CircleArrowRight = 0xF0A9, // fa-circle-arrow-right
	CircleArrowUp = 0xF0AA, // fa-circle-arrow-up
	CircleCheck = 0xF058, // fa-circle-check
	CircleChevronDown = 0xF13A, // fa-circle-chevron-down
	CircleChevronLeft = 0xF137, // fa-circle-chevron-left
	CircleChevronRight = 0xF138, // fa-circle-chevron-right
	CircleChevronUp = 0xF139, // fa-circle-chevron-up
	CircleDollarToSlot = 0xF4B9, // fa-circle-dollar-to-slot
	CircleDot = 0xF192, // fa-circle-dot
	CircleDown = 0xF358, // fa-circle-down
	CircleExclamation = 0xF06A, // fa-circle-exclamation
	CircleH = 0xF47E, // fa-circle-h
	CircleHalfStroke = 0xF042, // fa-circle-half-stroke
	CircleInfo = 0xF05A, // fa-circle-info
	CircleLeft = 0xF359, // fa-circle-left
	CircleMinus = 0xF056, // fa-circle-minus
	CircleNodes = 0xE4E2, // fa-circle-nodes
	CircleNotch = 0xF1CE, // fa-circle-notch
	CirclePause = 0xF28B, // fa-circle-pause
	CirclePlay = 0xF144, // fa-circle-play
	CirclePlus = 0xF055, // fa-circle-plus
	CircleQuestion = 0xF059, // fa-circle-question
	CircleRadiation = 0xF7BA, // fa-circle-radiation
	CircleRight = 0xF35A, // fa-circle-right
	CircleStop = 0xF28D, // fa-circle-stop
	CircleUp = 0xF35B, // fa-circle-up
	CircleUser = 0xF2BD, // fa-circle-user
	CircleXmark = 0xF057, // fa-circle-xmark
	City = 0xF64F, // fa-city
	Clapperboard = 0xE131, // fa-clapperboard
	Clipboard = 0xF328, // fa-clipboard
	ClipboardCheck = 0xF46C, // fa-clipboard-check
	ClipboardList = 0xF46D, // fa-clipboard-list
	ClipboardQuestion = 0xE4E3, // fa-clipboard-question
	ClipboardUser = 0xF7F3, // fa-clipboard-user
	Clock = 0xF017, // fa-clock
	ClockRotateLeft = 0xF1DA, // fa-clock-rotate-left
	Clone = 0xF24D, // fa-clone
	ClosedCaptioning = 0xF20A, // fa-closed-captioning
	Cloud = 0xF0C2, // fa-cloud
	CloudArrowDown = 0xF0ED, // fa-cloud-arrow-down
	CloudArrowUp = 0xF0EE, // fa-cloud-arrow-up
	CloudBolt = 0xF76C, // fa-cloud-bolt
	CloudMeatball = 0xF73B, // fa-cloud-meatball
	CloudMoon = 0xF6C3, // fa-cloud-moon
	CloudMoonRain = 0xF73C, // fa-cloud-moon-rain
	CloudRain = 0xF73D, // fa-cloud-rain
	CloudShowersHeavy = 0xF740, // fa-cloud-showers-heavy
	CloudShowersWater = 0xE4E4, // fa-cloud-showers-water
	CloudSun = 0xF6C4, // fa-cloud-sun
	CloudSunRain = 0xF743, // fa-cloud-sun-rain
	Clover = 0xE139, // fa-clover
	Code = 0xF121, // fa-code
	CodeBranch = 0xF126, // fa-code-branch
	CodeCommit = 0xF386, // fa-code-commit
	CodeCompare = 0xE13A, // fa-code-compare
	CodeFork = 0xE13B, // fa-code-fork
	CodeMerge = 0xF387, // fa-code-merge
	CodePullRequest = 0xE13C, // fa-code-pull-request
	Coins = 0xF51E, // fa-coins
	ColonSign = 0xE140, // fa-colon-sign
	Comment = 0xF075, // fa-comment
	CommentDollar = 0xF651, // fa-comment-dollar
	CommentDots = 0xF4AD, // fa-comment-dots
	CommentMedical = 0xF7F5, // fa-comment-medical
	CommentNodes = 0xE696, // fa-comment-nodes
	CommentSlash = 0xF4B3, // fa-comment-slash
	CommentSms = 0xF7CD, // fa-comment-sms
	Comments = 0xF086, // fa-comments
	CommentsDollar = 0xF653, // fa-comments-dollar
	CompactDisc = 0xF51F, // fa-compact-disc
	Compass = 0xF14E, // fa-compass
	CompassDrafting = 0xF568, // fa-compass-drafting
	Compress = 0xF066, // fa-compress
	Computer = 0xE4E5, // fa-computer
	ComputerMouse = 0xF8CC, // fa-computer-mouse
	Cookie = 0xF563, // fa-cookie
	CookieBite = 0xF564, // fa-cookie-bite
	Copy = 0xF0C5, // fa-copy
	Copyright = 0xF1F9, // fa-copyright
	Couch = 0xF4B8, // fa-couch
	Cow = 0xF6C8, // fa-cow
	CreditCard = 0xF09D, // fa-credit-card
	Crop = 0xF125, // fa-crop
	CropSimple = 0xF565, // fa-crop-simple
	Cross = 0xF654, // fa-cross
	Crosshairs = 0xF05B, // fa-crosshairs
	Crow = 0xF520, // fa-crow
	Crown = 0xF521, // fa-crown
	Crutch = 0xF7F7, // fa-crutch
	CruzeiroSign = 0xE152, // fa-cruzeiro-sign
	Cube = 0xF1B2, // fa-cube
	Cubes = 0xF1B3, // fa-cubes
	CubesStacked = 0xE4E6, // fa-cubes-stacked
	D = 0x44, // fa-d
	Database = 0xF1C0, // fa-database
	DeleteLeft = 0xF55A, // fa-delete-left
	Democrat = 0xF747, // fa-democrat
	Desktop = 0xF390, // fa-desktop
	Dharmachakra = 0xF655, // fa-dharmachakra
	DiagramNext = 0xE476, // fa-diagram-next
	DiagramPredecessor = 0xE477, // fa-diagram-predecessor
	DiagramProject = 0xF542, // fa-diagram-project
	DiagramSuccessor = 0xE47A, // fa-diagram-successor
	Diamond = 0xF219, // fa-diamond
	DiamondTurnRight = 0xF5EB, // fa-diamond-turn-right
	Dice = 0xF522, // fa-dice
	DiceD20 = 0xF6CF, // fa-dice-d20
	DiceD6 = 0xF6D1, // fa-dice-d6
	DiceFive = 0xF523, // fa-dice-five
	DiceFour = 0xF524, // fa-dice-four
	DiceOne = 0xF525, // fa-dice-one
	DiceSix = 0xF526, // fa-dice-six
	DiceThree = 0xF527, // fa-dice-three
	DiceTwo = 0xF528, // fa-dice-two
	Disease = 0xF7FA, // fa-disease
	Display = 0xE163, // fa-display
	Divide = 0xF529, // fa-divide
	Dna = 0xF471, // fa-dna
	Dog = 0xF6D3, // fa-dog
	DollarSign = 0x24, // fa-dollar-sign
	Dolly = 0xF472, // fa-dolly
	DongSign = 0xE169, // fa-dong-sign
	DoorClosed = 0xF52A, // fa-door-closed
	DoorOpen = 0xF52B, // fa-door-open
	Dove = 0xF4BA, // fa-dove
	DownLeftAndUpRightToCenter = 0xF422, // fa-down-left-and-up-right-to-center
	DownLong = 0xF309, // fa-down-long
	Download = 0xF019, // fa-download
	Dragon = 0xF6D5, // fa-dragon
	DrawPolygon = 0xF5EE, // fa-draw-polygon
	Droplet = 0xF043, // fa-droplet
	DropletSlash = 0xF5C7, // fa-droplet-slash
	Drum = 0xF569, // fa-drum
	DrumSteelpan = 0xF56A, // fa-drum-steelpan
	DrumstickBite = 0xF6D7, // fa-drumstick-bite
	Dumbbell = 0xF44B, // fa-dumbbell
	Dumpster = 0xF793, // fa-dumpster
	DumpsterFire = 0xF794, // fa-dumpster-fire
	Dungeon = 0xF6D9, // fa-dungeon
	E = 0x45, // fa-e
	EarDeaf = 0xF2A4, // fa-ear-deaf
	EarListen = 0xF2A2, // fa-ear-listen
	EarthAfrica = 0xF57C, // fa-earth-africa
	EarthAmericas = 0xF57D, // fa-earth-americas
	EarthAsia = 0xF57E, // fa-earth-asia
	EarthEurope = 0xF7A2, // fa-earth-europe
	EarthOceania = 0xE47B, // fa-earth-oceania
	Egg = 0xF7FB, // fa-egg
	Eject = 0xF052, // fa-eject
	Elevator = 0xE16D, // fa-elevator
	Ellipsis = 0xF141, // fa-ellipsis
	EllipsisVertical = 0xF142, // fa-ellipsis-vertical
	Envelope = 0xF0E0, // fa-envelope
	EnvelopeCircleCheck = 0xE4E8, // fa-envelope-circle-check
	EnvelopeOpen = 0xF2B6, // fa-envelope-open
	EnvelopeOpenText = 0xF658, // fa-envelope-open-text
	EnvelopesBulk = 0xF674, // fa-envelopes-bulk
	Equals = 0x3D, // fa-equals
	Eraser = 0xF12D, // fa-eraser
	Ethernet = 0xF796, // fa-ethernet
	EuroSign = 0xF153, // fa-euro-sign
	Exclamation = 0x21, // fa-exclamation
	Expand = 0xF065, // fa-expand
	Explosion = 0xE4E9, // fa-explosion
	Eye = 0xF06E, // fa-eye
	EyeDropper = 0xF1FB, // fa-eye-dropper
	EyeLowVision = 0xF2A8, // fa-eye-low-vision
	EyeSlash = 0xF070, // fa-eye-slash
	F = 0x46, // fa-f
	FaceAngry = 0xF556, // fa-face-angry
	FaceDizzy = 0xF567, // fa-face-dizzy
	FaceFlushed = 0xF579, // fa-face-flushed
	FaceFrown = 0xF119, // fa-face-frown
	FaceFrownOpen = 0xF57A, // fa-face-frown-open
	FaceGrimace = 0xF57F, // fa-face-grimace
	FaceGrin = 0xF580, // fa-face-grin
	FaceGrinBeam = 0xF582, // fa-face-grin-beam
	FaceGrinBeamSweat = 0xF583, // fa-face-grin-beam-sweat
	FaceGrinHearts = 0xF584, // fa-face-grin-hearts
	FaceGrinSquint = 0xF585, // fa-face-grin-squint
	FaceGrinSquintTears = 0xF586, // fa-face-grin-squint-tears
	FaceGrinStars = 0xF587, // fa-face-grin-stars
	FaceGrinTears = 0xF588, // fa-face-grin-tears
	FaceGrinTongue = 0xF589, // fa-face-grin-tongue
	FaceGrinTongueSquint = 0xF58A, // fa-face-grin-tongue-squint
	FaceGrinTongueWink = 0xF58B, // fa-face-grin-tongue-wink
	FaceGrinWide = 0xF581, // fa-face-grin-wide
	FaceGrinWink = 0xF58C, // fa-face-grin-wink
	FaceKiss = 0xF596, // fa-face-kiss
	FaceKissBeam = 0xF597, // fa-face-kiss-beam
	FaceKissWinkHeart = 0xF598, // fa-face-kiss-wink-heart
	FaceLaugh = 0xF599, // fa-face-laugh
	FaceLaughBeam = 0xF59A, // fa-face-laugh-beam
	FaceLaughSquint = 0xF59B, // fa-face-laugh-squint
	FaceLaughWink = 0xF59C, // fa-face-laugh-wink
	FaceMeh = 0xF11A, // fa-face-meh
	FaceMehBlank = 0xF5A4, // fa-face-meh-blank
	FaceRollingEyes = 0xF5A5, // fa-face-rolling-eyes
	FaceSadCry = 0xF5B3, // fa-face-sad-cry
	FaceSadTear = 0xF5B4, // fa-face-sad-tear
	FaceSmile = 0xF118, // fa-face-smile
	FaceSmileBeam = 0xF5B8, // fa-face-smile-beam
	FaceSmileWink = 0xF4DA, // fa-face-smile-wink
	FaceSurprise = 0xF5C2, // fa-face-surprise
	FaceTired = 0xF5C8, // fa-face-tired
	Fan = 0xF863, // fa-fan
	Faucet = 0xE005, // fa-faucet
	FaucetDrip = 0xE006, // fa-faucet-drip
	Fax = 0xF1AC, // fa-fax
	Feather = 0xF52D, // fa-feather
	FeatherPointed = 0xF56B, // fa-feather-pointed
	Ferry = 0xE4EA, // fa-ferry
	File = 0xF15B, // fa-file
	FileArrowDown = 0xF56D, // fa-file-arrow-down
	FileArrowUp = 0xF574, // fa-file-arrow-up
	FileAudio = 0xF1C7, // fa-file-audio
	FileCircleCheck = 0xE5A0, // fa-file-circle-check
	FileCircleExclamation = 0xE4EB, // fa-file-circle-exclamation
	FileCircleMinus = 0xE4ED, // fa-file-circle-minus
	FileCirclePlus = 0xE494, // fa-file-circle-plus
	FileCircleQuestion = 0xE4EF, // fa-file-circle-question
	FileCircleXmark = 0xE5A1, // fa-file-circle-xmark
	FileCode = 0xF1C9, // fa-file-code
	FileContract = 0xF56C, // fa-file-contract
	FileCsv = 0xF6DD, // fa-file-csv
	FileExcel = 0xF1C3, // fa-file-excel
	FileExport = 0xF56E, // fa-file-export
	FileFragment = 0xE697, // fa-file-fragment
	FileHalfDashed = 0xE698, // fa-file-half-dashed
	FileImage = 0xF1C5, // fa-file-image
	FileImport = 0xF56F, // fa-file-import
	FileInvoice = 0xF570, // fa-file-invoice
	FileInvoiceDollar = 0xF571, // fa-file-invoice-dollar
	FileLines = 0xF15C, // fa-file-lines
	FileMedical = 0xF477, // fa-file-medical
	FilePdf = 0xF1C1, // fa-file-pdf
	FilePen = 0xF31C, // fa-file-pen
	FilePowerpoint = 0xF1C4, // fa-file-powerpoint
	FilePrescription = 0xF572, // fa-file-prescription
	FileShield = 0xE4F0, // fa-file-shield
	FileSignature = 0xF573, // fa-file-signature
	FileVideo = 0xF1C8, // fa-file-video
	FileWaveform = 0xF478, // fa-file-waveform
	FileWord = 0xF1C2, // fa-file-word
	FileZipper = 0xF1C6, // fa-file-zipper
	Fill = 0xF575, // fa-fill
	FillDrip = 0xF576, // fa-fill-drip
	Film = 0xF008, // fa-film
	Filter = 0xF0B0, // fa-filter
	FilterCircleDollar = 0xF662, // fa-filter-circle-dollar
	FilterCircleXmark = 0xE17B, // fa-filter-circle-xmark
	Fingerprint = 0xF577, // fa-fingerprint
	Fire = 0xF06D, // fa-fire
	FireBurner = 0xE4F1, // fa-fire-burner
	FireExtinguisher = 0xF134, // fa-fire-extinguisher
	FireFlameCurved = 0xF7E4, // fa-fire-flame-curved
	FireFlameSimple = 0xF46A, // fa-fire-flame-simple
	Fish = 0xF578, // fa-fish
	FishFins = 0xE4F2, // fa-fish-fins
	Flag = 0xF024, // fa-flag
	FlagCheckered = 0xF11E, // fa-flag-checkered
	FlagUsa = 0xF74D, // fa-flag-usa
	Flask = 0xF0C3, // fa-flask
	FlaskVial = 0xE4F3, // fa-flask-vial
	FloppyDisk = 0xF0C7, // fa-floppy-disk
	FlorinSign = 0xE184, // fa-florin-sign
	Folder = 0xF07B, // fa-folder
	FolderClosed = 0xE185, // fa-folder-closed
	FolderMinus = 0xF65D, // fa-folder-minus
	FolderOpen = 0xF07C, // fa-folder-open
	FolderPlus = 0xF65E, // fa-folder-plus
	FolderTree = 0xF802, // fa-folder-tree
	Font = 0xF031, // fa-font
	FontAwesome = 0xF2B4, // fa-font-awesome
	Football = 0xF44E, // fa-football
	Forward = 0xF04E, // fa-forward
	ForwardFast = 0xF050, // fa-forward-fast
	ForwardStep = 0xF051, // fa-forward-step
	FrancSign = 0xE18F, // fa-franc-sign
	Frog = 0xF52E, // fa-frog
	Futbol = 0xF1E3, // fa-futbol
	G = 0x47, // fa-g
	Gamepad = 0xF11B, // fa-gamepad
	GasPump = 0xF52F, // fa-gas-pump
	Gauge = 0xF624, // fa-gauge
	GaugeHigh = 0xF625, // fa-gauge-high
	GaugeSimple = 0xF629, // fa-gauge-simple
	GaugeSimpleHigh = 0xF62A, // fa-gauge-simple-high
	Gavel = 0xF0E3, // fa-gavel
	Gear = 0xF013, // fa-gear
	Gears = 0xF085, // fa-gears
	Gem = 0xF3A5, // fa-gem
	Genderless = 0xF22D, // fa-genderless
	Ghost = 0xF6E2, // fa-ghost
	Gift = 0xF06B, // fa-gift
	Gifts = 0xF79C, // fa-gifts
	GlassWater = 0xE4F4, // fa-glass-water
	GlassWaterDroplet = 0xE4F5, // fa-glass-water-droplet
	Glasses = 0xF530, // fa-glasses
	Globe = 0xF0AC, // fa-globe
	GolfBallTee = 0xF450, // fa-golf-ball-tee
	Gopuram = 0xF664, // fa-gopuram
	GraduationCap = 0xF19D, // fa-graduation-cap
	GreaterThan = 0x3E, // fa-greater-than
	GreaterThanEqual = 0xF532, // fa-greater-than-equal
	Grip = 0xF58D, // fa-grip
	GripLines = 0xF7A4, // fa-grip-lines
	GripLinesVertical = 0xF7A5, // fa-grip-lines-vertical
	GripVertical = 0xF58E, // fa-grip-vertical
	GroupArrowsRotate = 0xE4F6, // fa-group-arrows-rotate
	GuaraniSign = 0xE19A, // fa-guarani-sign
	Guitar = 0xF7A6, // fa-guitar
	Gun = 0xE19B, // fa-gun
	H = 0x48, // fa-h
	Hammer = 0xF6E3, // fa-hammer
	Hamsa = 0xF665, // fa-hamsa
	Hand = 0xF256, // fa-hand
	HandBackFist = 0xF255, // fa-hand-back-fist
	HandDots = 0xF461, // fa-hand-dots
	HandFist = 0xF6DE, // fa-hand-fist
	HandHolding = 0xF4BD, // fa-hand-holding
	HandHoldingDollar = 0xF4C0, // fa-hand-holding-dollar
	HandHoldingDroplet = 0xF4C1, // fa-hand-holding-droplet
	HandHoldingHand = 0xE4F7, // fa-hand-holding-hand
	HandHoldingHeart = 0xF4BE, // fa-hand-holding-heart
	HandHoldingMedical = 0xE05C, // fa-hand-holding-medical
	HandLizard = 0xF258, // fa-hand-lizard
	HandMiddleFinger = 0xF806, // fa-hand-middle-finger
	HandPeace = 0xF25B, // fa-hand-peace
	HandPointDown = 0xF0A7, // fa-hand-point-down
	HandPointLeft = 0xF0A5, // fa-hand-point-left
	HandPointRight = 0xF0A4, // fa-hand-point-right
	HandPointUp = 0xF0A6, // fa-hand-point-up
	HandPointer = 0xF25A, // fa-hand-pointer
	HandScissors = 0xF257, // fa-hand-scissors
	HandSparkles = 0xE05D, // fa-hand-sparkles
	HandSpock = 0xF259, // fa-hand-spock
	Handcuffs = 0xE4F8, // fa-handcuffs
	Hands = 0xF2A7, // fa-hands
	HandsAslInterpreting = 0xF2A3, // fa-hands-asl-interpreting
	HandsBound = 0xE4F9, // fa-hands-bound
	HandsBubbles = 0xE05E, // fa-hands-bubbles
	HandsClapping = 0xE1A8, // fa-hands-clapping
	HandsHolding = 0xF4C2, // fa-hands-holding
	HandsHoldingChild = 0xE4FA, // fa-hands-holding-child
	HandsHoldingCircle = 0xE4FB, // fa-hands-holding-circle
	HandsPraying = 0xF684, // fa-hands-praying
	Handshake = 0xF2B5, // fa-handshake
	HandshakeAngle = 0xF4C4, // fa-handshake-angle
	HandshakeSimple = 0xF4C6, // fa-handshake-simple
	HandshakeSimpleSlash = 0xE05F, // fa-handshake-simple-slash
	HandshakeSlash = 0xE060, // fa-handshake-slash
	Hanukiah = 0xF6E6, // fa-hanukiah
	HardDrive = 0xF0A0, // fa-hard-drive
	Hashtag = 0x23, // fa-hashtag
	HatCowboy = 0xF8C0, // fa-hat-cowboy
	HatCowboySide = 0xF8C1, // fa-hat-cowboy-side
	HatWizard = 0xF6E8, // fa-hat-wizard
	HeadSideCough = 0xE061, // fa-head-side-cough
	HeadSideCoughSlash = 0xE062, // fa-head-side-cough-slash
	HeadSideMask = 0xE063, // fa-head-side-mask
	HeadSideVirus = 0xE064, // fa-head-side-virus
	Heading = 0xF1DC, // fa-heading
	Headphones = 0xF025, // fa-headphones
	HeadphonesSimple = 0xF58F, // fa-headphones-simple
	Headset = 0xF590, // fa-headset
	Heart = 0xF004, // fa-heart
	HeartCircleBolt = 0xE4FC, // fa-heart-circle-bolt
	HeartCircleCheck = 0xE4FD, // fa-heart-circle-check
	HeartCircleExclamation = 0xE4FE, // fa-heart-circle-exclamation
	HeartCircleMinus = 0xE4FF, // fa-heart-circle-minus
	HeartCirclePlus = 0xE500, // fa-heart-circle-plus
	HeartCircleXmark = 0xE501, // fa-heart-circle-xmark
	HeartCrack = 0xF7A9, // fa-heart-crack
	HeartPulse = 0xF21E, // fa-heart-pulse
	Helicopter = 0xF533, // fa-helicopter
	HelicopterSymbol = 0xE502, // fa-helicopter-symbol
	HelmetSafety = 0xF807, // fa-helmet-safety
	HelmetUn = 0xE503, // fa-helmet-un
	HexagonNodes = 0xE699, // fa-hexagon-nodes
	HexagonNodesBolt = 0xE69A, // fa-hexagon-nodes-bolt
	Highlighter = 0xF591, // fa-highlighter
	HillAvalanche = 0xE507, // fa-hill-avalanche
	HillRockslide = 0xE508, // fa-hill-rockslide
	Hippo = 0xF6ED, // fa-hippo
	HockeyPuck = 0xF453, // fa-hockey-puck
	HollyBerry = 0xF7AA, // fa-holly-berry
	Horse = 0xF6F0, // fa-horse
	HorseHead = 0xF7AB, // fa-horse-head
	Hospital = 0xF0F8, // fa-hospital
	HospitalUser = 0xF80D, // fa-hospital-user
	HotTubPerson = 0xF593, // fa-hot-tub-person
	Hotdog = 0xF80F, // fa-hotdog
	Hotel = 0xF594, // fa-hotel
	Hourglass = 0xF254, // fa-hourglass
	HourglassEnd = 0xF253, // fa-hourglass-end
	HourglassHalf = 0xF252, // fa-hourglass-half
	HourglassStart = 0xF251, // fa-hourglass-start
	House = 0xF015, // fa-house
	HouseChimney = 0xE3AF, // fa-house-chimney
	HouseChimneyCrack = 0xF6F1, // fa-house-chimney-crack
	HouseChimneyMedical = 0xF7F2, // fa-house-chimney-medical
	HouseChimneyUser = 0xE065, // fa-house-chimney-user
	HouseChimneyWindow = 0xE00D, // fa-house-chimney-window
	HouseCircleCheck = 0xE509, // fa-house-circle-check
	HouseCircleExclamation = 0xE50A, // fa-house-circle-exclamation
	HouseCircleXmark = 0xE50B, // fa-house-circle-xmark
	HouseCrack = 0xE3B1, // fa-house-crack
	HouseFire = 0xE50C, // fa-house-fire
	HouseFlag = 0xE50D, // fa-house-flag
	HouseFloodWater = 0xE50E, // fa-house-flood-water
	HouseFloodWaterCircleArrowRight = 0xE50F, // fa-house-flood-water-circle-arrow-right
	HouseLaptop = 0xE066, // fa-house-laptop
	HouseLock = 0xE510, // fa-house-lock
	HouseMedical = 0xE3B2, // fa-house-medical
	HouseMedicalCircleCheck = 0xE511, // fa-house-medical-circle-check
	HouseMedicalCircleExclamation = 0xE512, // fa-house-medical-circle-exclamation
	HouseMedicalCircleXmark = 0xE513, // fa-house-medical-circle-xmark
	HouseMedicalFlag = 0xE514, // fa-house-medical-flag
	HouseSignal = 0xE012, // fa-house-signal
	HouseTsunami = 0xE515, // fa-house-tsunami
	HouseUser = 0xE1B0, // fa-house-user
	HryvniaSign = 0xF6F2, // fa-hryvnia-sign
	Hurricane = 0xF751, // fa-hurricane
	I = 0x49, // fa-i
	ICursor = 0xF246, // fa-i-cursor
	IceCream = 0xF810, // fa-ice-cream
	Icicles = 0xF7AD, // fa-icicles
	Icons = 0xF86D, // fa-icons
	IdBadge = 0xF2C1, // fa-id-badge
	IdCard = 0xF2C2, // fa-id-card
	IdCardClip = 0xF47F, // fa-id-card-clip
	Igloo = 0xF7AE, // fa-igloo
	Image = 0xF03E, // fa-image
	ImagePortrait = 0xF3E0, // fa-image-portrait
	Images = 0xF302, // fa-images
	Inbox = 0xF01C, // fa-inbox
	Indent = 0xF03C, // fa-indent
	IndianRupeeSign = 0xE1BC, // fa-indian-rupee-sign
	Industry = 0xF275, // fa-industry
	Infinity = 0xF534, // fa-infinity
	Info = 0xF129, // fa-info
	Italic = 0xF033, // fa-italic
	J = 0x4A, // fa-j
	Jar = 0xE516, // fa-jar
	JarWheat = 0xE517, // fa-jar-wheat
	Jedi = 0xF669, // fa-jedi
	JetFighter = 0xF0FB, // fa-jet-fighter
	JetFighterUp = 0xE518, // fa-jet-fighter-up
	Joint = 0xF595, // fa-joint
	JugDetergent = 0xE519, // fa-jug-detergent
	K = 0x4B, // fa-k
	Kaaba = 0xF66B, // fa-kaaba
	Key = 0xF084, // fa-key
	Keyboard = 0xF11C, // fa-keyboard
	Khanda = 0xF66D, // fa-khanda
	KipSign = 0xE1C4, // fa-kip-sign
	KitMedical = 0xF479, // fa-kit-medical
	KitchenSet = 0xE51A, // fa-kitchen-set
	KiwiBird = 0xF535, // fa-kiwi-bird
	L = 0x4C, // fa-l
	LandMineOn = 0xE51B, // fa-land-mine-on
	Landmark = 0xF66F, // fa-landmark
	LandmarkDome = 0xF752, // fa-landmark-dome
	LandmarkFlag = 0xE51C, // fa-landmark-flag
	Language = 0xF1AB, // fa-language
	Laptop = 0xF109, // fa-laptop
	LaptopCode = 0xF5FC, // fa-laptop-code
	LaptopFile = 0xE51D, // fa-laptop-file
	LaptopMedical = 0xF812, // fa-laptop-medical
	LariSign = 0xE1C8, // fa-lari-sign
	LayerGroup = 0xF5FD, // fa-layer-group
	Leaf = 0xF06C, // fa-leaf
	LeftLong = 0xF30A, // fa-left-long
	LeftRight = 0xF337, // fa-left-right
	Lemon = 0xF094, // fa-lemon
	LessThan = 0x3C, // fa-less-than
	LessThanEqual = 0xF537, // fa-less-than-equal
	LifeRing = 0xF1CD, // fa-life-ring
	Lightbulb = 0xF0EB, // fa-lightbulb
	LinesLeaning = 0xE51E, // fa-lines-leaning
	Link = 0xF0C1, // fa-link
	LinkSlash = 0xF127, // fa-link-slash
	LiraSign = 0xF195, // fa-lira-sign
	List = 0xF03A, // fa-list
	ListCheck = 0xF0AE, // fa-list-check
	ListOl = 0xF0CB, // fa-list-ol
	ListUl = 0xF0CA, // fa-list-ul
	LitecoinSign = 0xE1D3, // fa-litecoin-sign
	LocationArrow = 0xF124, // fa-location-arrow
	LocationCrosshairs = 0xF601, // fa-location-crosshairs
	LocationDot = 0xF3C5, // fa-location-dot
	LocationPin = 0xF041, // fa-location-pin
	LocationPinLock = 0xE51F, // fa-location-pin-lock
	Lock = 0xF023, // fa-lock
	LockOpen = 0xF3C1, // fa-lock-open
	Locust = 0xE520, // fa-locust
	Lungs = 0xF604, // fa-lungs
	LungsVirus = 0xE067, // fa-lungs-virus
	M = 0x4D, // fa-m
	Magnet = 0xF076, // fa-magnet
	MagnifyingGlass = 0xF002, // fa-magnifying-glass
	MagnifyingGlassArrowRight = 0xE521, // fa-magnifying-glass-arrow-right
	MagnifyingGlassChart = 0xE522, // fa-magnifying-glass-chart
	MagnifyingGlassDollar = 0xF688, // fa-magnifying-glass-dollar
	MagnifyingGlassLocation = 0xF689, // fa-magnifying-glass-location
	MagnifyingGlassMinus = 0xF010, // fa-magnifying-glass-minus
	MagnifyingGlassPlus = 0xF00E, // fa-magnifying-glass-plus
	ManatSign = 0xE1D5, // fa-manat-sign
	Map = 0xF279, // fa-map
	MapLocation = 0xF59F, // fa-map-location
	MapLocationDot = 0xF5A0, // fa-map-location-dot
	MapPin = 0xF276, // fa-map-pin
	Marker = 0xF5A1, // fa-marker
	Mars = 0xF222, // fa-mars
	MarsAndVenus = 0xF224, // fa-mars-and-venus
	MarsAndVenusBurst = 0xE523, // fa-mars-and-venus-burst
	MarsDouble = 0xF227, // fa-mars-double
	MarsStroke = 0xF229, // fa-mars-stroke
	MarsStrokeRight = 0xF22B, // fa-mars-stroke-right
	MarsStrokeUp = 0xF22A, // fa-mars-stroke-up
	MartiniGlass = 0xF57B, // fa-martini-glass
	MartiniGlassCitrus = 0xF561, // fa-martini-glass-citrus
	MartiniGlassEmpty = 0xF000, // fa-martini-glass-empty
	Mask = 0xF6FA, // fa-mask
	MaskFace = 0xE1D7, // fa-mask-face
	MaskVentilator = 0xE524, // fa-mask-ventilator
	MasksTheater = 0xF630, // fa-masks-theater
	MattressPillow = 0xE525, // fa-mattress-pillow
	Maximize = 0xF31E, // fa-maximize
	Medal = 0xF5A2, // fa-medal
	Memory = 0xF538, // fa-memory
	Menorah = 0xF676, // fa-menorah
	Mercury = 0xF223, // fa-mercury
	Message = 0xF27A, // fa-message
	Meteor = 0xF753, // fa-meteor
	Microchip = 0xF2DB, // fa-microchip
	Microphone = 0xF130, // fa-microphone
	MicrophoneLines = 0xF3C9, // fa-microphone-lines
	MicrophoneLinesSlash = 0xF539, // fa-microphone-lines-slash
	MicrophoneSlash = 0xF131, // fa-microphone-slash
	Microscope = 0xF610, // fa-microscope
	MillSign = 0xE1ED, // fa-mill-sign
	Minimize = 0xF78C, // fa-minimize
	Minus = 0xF068, // fa-minus
	Mitten = 0xF7B5, // fa-mitten
	Mobile = 0xF3CE, // fa-mobile
	MobileButton = 0xF10B, // fa-mobile-button
	MobileRetro = 0xE527, // fa-mobile-retro
	MobileScreen = 0xF3CF, // fa-mobile-screen
	MobileScreenButton = 0xF3CD, // fa-mobile-screen-button
	MoneyBill = 0xF0D6, // fa-money-bill
	MoneyBill1 = 0xF3D1, // fa-money-bill-1
	MoneyBill1Wave = 0xF53B, // fa-money-bill-1-wave
	MoneyBillTransfer = 0xE528, // fa-money-bill-transfer
	MoneyBillTrendUp = 0xE529, // fa-money-bill-trend-up
	MoneyBillWave = 0xF53A, // fa-money-bill-wave
	MoneyBillWheat = 0xE52A, // fa-money-bill-wheat
	MoneyBills = 0xE1F3, // fa-money-bills
	MoneyCheck = 0xF53C, // fa-money-check
	MoneyCheckDollar = 0xF53D, // fa-money-check-dollar
	Monument = 0xF5A6, // fa-monument
	Moon = 0xF186, // fa-moon
	MortarPestle = 0xF5A7, // fa-mortar-pestle
	Mosque = 0xF678, // fa-mosque
	Mosquito = 0xE52B, // fa-mosquito
	MosquitoNet = 0xE52C, // fa-mosquito-net
	Motorcycle = 0xF21C, // fa-motorcycle
	Mound = 0xE52D, // fa-mound
	Mountain = 0xF6FC, // fa-mountain
	MountainCity = 0xE52E, // fa-mountain-city
	MountainSun = 0xE52F, // fa-mountain-sun
	MugHot = 0xF7B6, // fa-mug-hot
	MugSaucer = 0xF0F4, // fa-mug-saucer
	Music = 0xF001, // fa-music
	N = 0x4E, // fa-n
	NairaSign = 0xE1F6, // fa-naira-sign
	NetworkWired = 0xF6FF, // fa-network-wired
	Neuter = 0xF22C, // fa-neuter
	Newspaper = 0xF1EA, // fa-newspaper
	NotEqual = 0xF53E, // fa-not-equal
	Notdef = 0xE1FE, // fa-notdef
	NoteSticky = 0xF249, // fa-note-sticky
	NotesMedical = 0xF481, // fa-notes-medical
	O = 0x4F, // fa-o
	ObjectGroup = 0xF247, // fa-object-group
	ObjectUngroup = 0xF248, // fa-object-ungroup
	OilCan = 0xF613, // fa-oil-can
	OilWell = 0xE532, // fa-oil-well
	Om = 0xF679, // fa-om
	Otter = 0xF700, // fa-otter
	Outdent = 0xF03B, // fa-outdent
	P = 0x50, // fa-p
	Pager = 0xF815, // fa-pager
	PaintRoller = 0xF5AA, // fa-paint-roller
	Paintbrush = 0xF1FC, // fa-paintbrush
	Palette = 0xF53F, // fa-palette
	Pallet = 0xF482, // fa-pallet
	Panorama = 0xE209, // fa-panorama
	PaperPlane = 0xF1D8, // fa-paper-plane
	Paperclip = 0xF0C6, // fa-paperclip
	ParachuteBox = 0xF4CD, // fa-parachute-box
	Paragraph = 0xF1DD, // fa-paragraph
	Passport = 0xF5AB, // fa-passport
	Paste = 0xF0EA, // fa-paste
	Pause = 0xF04C, // fa-pause
	Paw = 0xF1B0, // fa-paw
	Peace = 0xF67C, // fa-peace
	Pen = 0xF304, // fa-pen
	PenClip = 0xF305, // fa-pen-clip
	PenFancy = 0xF5AC, // fa-pen-fancy
	PenNib = 0xF5AD, // fa-pen-nib
	PenRuler = 0xF5AE, // fa-pen-ruler
	PenToSquare = 0xF044, // fa-pen-to-square
	Pencil = 0xF303, // fa-pencil
	PeopleArrows = 0xE068, // fa-people-arrows
	PeopleCarryBox = 0xF4CE, // fa-people-carry-box
	PeopleGroup = 0xE533, // fa-people-group
	PeopleLine = 0xE534, // fa-people-line
	PeoplePulling = 0xE535, // fa-people-pulling
	PeopleRobbery = 0xE536, // fa-people-robbery
	PeopleRoof = 0xE537, // fa-people-roof
	PepperHot = 0xF816, // fa-pepper-hot
	Percent = 0x25, // fa-percent
	Person = 0xF183, // fa-person
	PersonArrowDownToLine = 0xE538, // fa-person-arrow-down-to-line
	PersonArrowUpFromLine = 0xE539, // fa-person-arrow-up-from-line
	PersonBiking = 0xF84A, // fa-person-biking
	PersonBooth = 0xF756, // fa-person-booth
	PersonBreastfeeding = 0xE53A, // fa-person-breastfeeding
	PersonBurst = 0xE53B, // fa-person-burst
	PersonCane = 0xE53C, // fa-person-cane
	PersonChalkboard = 0xE53D, // fa-person-chalkboard
	PersonCircleCheck = 0xE53E, // fa-person-circle-check
	PersonCircleExclamation = 0xE53F, // fa-person-circle-exclamation
	PersonCircleMinus = 0xE540, // fa-person-circle-minus
	PersonCirclePlus = 0xE541, // fa-person-circle-plus
	PersonCircleQuestion = 0xE542, // fa-person-circle-question
	PersonCircleXmark = 0xE543, // fa-person-circle-xmark
	PersonDigging = 0xF85E, // fa-person-digging
	PersonDotsFromLine = 0xF470, // fa-person-dots-from-line
	PersonDress = 0xF182, // fa-person-dress
	PersonDressBurst = 0xE544, // fa-person-dress-burst
	PersonDrowning = 0xE545, // fa-person-drowning
	PersonFalling = 0xE546, // fa-person-falling
	PersonFallingBurst = 0xE547, // fa-person-falling-burst
	PersonHalfDress = 0xE548, // fa-person-half-dress
	PersonHarassing = 0xE549, // fa-person-harassing
	PersonHiking = 0xF6EC, // fa-person-hiking
	PersonMilitaryPointing = 0xE54A, // fa-person-military-pointing
	PersonMilitaryRifle = 0xE54B, // fa-person-military-rifle
	PersonMilitaryToPerson = 0xE54C, // fa-person-military-to-person
	PersonPraying = 0xF683, // fa-person-praying
	PersonPregnant = 0xE31E, // fa-person-pregnant
	PersonRays = 0xE54D, // fa-person-rays
	PersonRifle = 0xE54E, // fa-person-rifle
	PersonRunning = 0xF70C, // fa-person-running
	PersonShelter = 0xE54F, // fa-person-shelter
	PersonSkating = 0xF7C5, // fa-person-skating
	PersonSkiing = 0xF7C9, // fa-person-skiing
	PersonSkiingNordic = 0xF7CA, // fa-person-skiing-nordic
	PersonSnowboarding = 0xF7CE, // fa-person-snowboarding
	PersonSwimming = 0xF5C4, // fa-person-swimming
	PersonThroughWindow = 0xE5A9, // fa-person-through-window
	PersonWalking = 0xF554, // fa-person-walking
	PersonWalkingArrowLoopLeft = 0xE551, // fa-person-walking-arrow-loop-left
	PersonWalkingArrowRight = 0xE552, // fa-person-walking-arrow-right
	PersonWalkingDashedLineArrowRight = 0xE553, // fa-person-walking-dashed-line-arrow-right
	PersonWalkingLuggage = 0xE554, // fa-person-walking-luggage
	PersonWalkingWithCane = 0xF29D, // fa-person-walking-with-cane
	PesetaSign = 0xE221, // fa-peseta-sign
	PesoSign = 0xE222, // fa-peso-sign
	Phone = 0xF095, // fa-phone
	PhoneFlip = 0xF879, // fa-phone-flip
	PhoneSlash = 0xF3DD, // fa-phone-slash
	PhoneVolume = 0xF2A0, // fa-phone-volume
	PhotoFilm = 0xF87C, // fa-photo-film
	PiggyBank = 0xF4D3, // fa-piggy-bank
	Pills = 0xF484, // fa-pills
	PizzaSlice = 0xF818, // fa-pizza-slice
	PlaceOfWorship = 0xF67F, // fa-place-of-worship
	Plane = 0xF072, // fa-plane
	PlaneArrival = 0xF5AF, // fa-plane-arrival
	PlaneCircleCheck = 0xE555, // fa-plane-circle-check
	PlaneCircleExclamation = 0xE556, // fa-plane-circle-exclamation
	PlaneCircleXmark = 0xE557, // fa-plane-circle-xmark
	PlaneDeparture = 0xF5B0, // fa-plane-departure
	PlaneLock = 0xE558, // fa-plane-lock
	PlaneSlash = 0xE069, // fa-plane-slash
	PlaneUp = 0xE22D, // fa-plane-up
	PlantWilt = 0xE5AA, // fa-plant-wilt
	PlateWheat = 0xE55A, // fa-plate-wheat
	Play = 0xF04B, // fa-play
	Plug = 0xF1E6, // fa-plug
	PlugCircleBolt = 0xE55B, // fa-plug-circle-bolt
	PlugCircleCheck = 0xE55C, // fa-plug-circle-check
	PlugCircleExclamation = 0xE55D, // fa-plug-circle-exclamation
	PlugCircleMinus = 0xE55E, // fa-plug-circle-minus
	PlugCirclePlus = 0xE55F, // fa-plug-circle-plus
	PlugCircleXmark = 0xE560, // fa-plug-circle-xmark
	Plus = 0x2B, // fa-plus
	PlusMinus = 0xE43C, // fa-plus-minus
	Podcast = 0xF2CE, // fa-podcast
	Poo = 0xF2FE, // fa-poo
	PooStorm = 0xF75A, // fa-poo-storm
	Poop = 0xF619, // fa-poop
	PowerOff = 0xF011, // fa-power-off
	Prescription = 0xF5B1, // fa-prescription
	PrescriptionBottle = 0xF485, // fa-prescription-bottle
	PrescriptionBottleMedical = 0xF486, // fa-prescription-bottle-medical
	Print = 0xF02F, // fa-print
	PumpMedical = 0xE06A, // fa-pump-medical
	PumpSoap = 0xE06B, // fa-pump-soap
	PuzzlePiece = 0xF12E, // fa-puzzle-piece
	Q = 0x51, // fa-q
	Qrcode = 0xF029, // fa-qrcode
	Question = 0x3F, // fa-question
	QuoteLeft = 0xF10D, // fa-quote-left
	QuoteRight = 0xF10E, // fa-quote-right
	R = 0x52, // fa-r
	Radiation = 0xF7B9, // fa-radiation
	Radio = 0xF8D7, // fa-radio
	Rainbow = 0xF75B, // fa-rainbow
	RankingStar = 0xE561, // fa-ranking-star
	Receipt = 0xF543, // fa-receipt
	RecordVinyl = 0xF8D9, // fa-record-vinyl
	RectangleAd = 0xF641, // fa-rectangle-ad
	RectangleList = 0xF022, // fa-rectangle-list
	RectangleXmark = 0xF410, // fa-rectangle-xmark
	Recycle = 0xF1B8, // fa-recycle
	Registered = 0xF25D, // fa-registered
	Repeat = 0xF363, // fa-repeat
	Reply = 0xF3E5, // fa-reply
	ReplyAll = 0xF122, // fa-reply-all
	Republican = 0xF75E, // fa-republican
	Restroom = 0xF7BD, // fa-restroom
	Retweet = 0xF079, // fa-retweet
	Ribbon = 0xF4D6, // fa-ribbon
	RightFromBracket = 0xF2F5, // fa-right-from-bracket
	RightLeft = 0xF362, // fa-right-left
	RightLong = 0xF30B, // fa-right-long
	RightToBracket = 0xF2F6, // fa-right-to-bracket
	Ring = 0xF70B, // fa-ring
	Road = 0xF018, // fa-road
	RoadBarrier = 0xE562, // fa-road-barrier
	RoadBridge = 0xE563, // fa-road-bridge
	RoadCircleCheck = 0xE564, // fa-road-circle-check
	RoadCircleExclamation = 0xE565, // fa-road-circle-exclamation
	RoadCircleXmark = 0xE566, // fa-road-circle-xmark
	RoadLock = 0xE567, // fa-road-lock
	RoadSpikes = 0xE568, // fa-road-spikes
	Robot = 0xF544, // fa-robot
	Rocket = 0xF135, // fa-rocket
	Rotate = 0xF2F1, // fa-rotate
	RotateLeft = 0xF2EA, // fa-rotate-left
	RotateRight = 0xF2F9, // fa-rotate-right
	Route = 0xF4D7, // fa-route
	Rss = 0xF09E, // fa-rss
	RubleSign = 0xF158, // fa-ruble-sign
	Rug = 0xE569, // fa-rug
	Ruler = 0xF545, // fa-ruler
	RulerCombined = 0xF546, // fa-ruler-combined
	RulerHorizontal = 0xF547, // fa-ruler-horizontal
	RulerVertical = 0xF548, // fa-ruler-vertical
	RupeeSign = 0xF156, // fa-rupee-sign
	RupiahSign = 0xE23D, // fa-rupiah-sign
	S = 0x53, // fa-s
	SackDollar = 0xF81D, // fa-sack-dollar
	SackXmark = 0xE56A, // fa-sack-xmark
	Sailboat = 0xE445, // fa-sailboat
	Satellite = 0xF7BF, // fa-satellite
	SatelliteDish = 0xF7C0, // fa-satellite-dish
	ScaleBalanced = 0xF24E, // fa-scale-balanced
	ScaleUnbalanced = 0xF515, // fa-scale-unbalanced
	ScaleUnbalancedFlip = 0xF516, // fa-scale-unbalanced-flip
	School = 0xF549, // fa-school
	SchoolCircleCheck = 0xE56B, // fa-school-circle-check
	SchoolCircleExclamation = 0xE56C, // fa-school-circle-exclamation
	SchoolCircleXmark = 0xE56D, // fa-school-circle-xmark
	SchoolFlag = 0xE56E, // fa-school-flag
	SchoolLock = 0xE56F, // fa-school-lock
	Scissors = 0xF0C4, // fa-scissors
	Screwdriver = 0xF54A, // fa-screwdriver
	ScrewdriverWrench = 0xF7D9, // fa-screwdriver-wrench
	Scroll = 0xF70E, // fa-scroll
	ScrollTorah = 0xF6A0, // fa-scroll-torah
	SdCard = 0xF7C2, // fa-sd-card
	Section = 0xE447, // fa-section
	Seedling = 0xF4D8, // fa-seedling
	Server = 0xF233, // fa-server
	Shapes = 0xF61F, // fa-shapes
	Share = 0xF064, // fa-share
	ShareFromSquare = 0xF14D, // fa-share-from-square
	ShareNodes = 0xF1E0, // fa-share-nodes
	SheetPlastic = 0xE571, // fa-sheet-plastic
	ShekelSign = 0xF20B, // fa-shekel-sign
	Shield = 0xF132, // fa-shield
	ShieldCat = 0xE572, // fa-shield-cat
	ShieldDog = 0xE573, // fa-shield-dog
	ShieldHalved = 0xF3ED, // fa-shield-halved
	ShieldHeart = 0xE574, // fa-shield-heart
	ShieldVirus = 0xE06C, // fa-shield-virus
	Ship = 0xF21A, // fa-ship
	Shirt = 0xF553, // fa-shirt
	ShoePrints = 0xF54B, // fa-shoe-prints
	Shop = 0xF54F, // fa-shop
	ShopLock = 0xE4A5, // fa-shop-lock
	ShopSlash = 0xE070, // fa-shop-slash
	Shower = 0xF2CC, // fa-shower
	Shrimp = 0xE448, // fa-shrimp
	Shuffle = 0xF074, // fa-shuffle
	ShuttleSpace = 0xF197, // fa-shuttle-space
	SignHanging = 0xF4D9, // fa-sign-hanging
	Signal = 0xF012, // fa-signal
	Signature = 0xF5B7, // fa-signature
	SignsPost = 0xF277, // fa-signs-post
	SimCard = 0xF7C4, // fa-sim-card
	Sink = 0xE06D, // fa-sink
	Sitemap = 0xF0E8, // fa-sitemap
	Skull = 0xF54C, // fa-skull
	SkullCrossbones = 0xF714, // fa-skull-crossbones
	Slash = 0xF715, // fa-slash
	Sleigh = 0xF7CC, // fa-sleigh
	Sliders = 0xF1DE, // fa-sliders
	Smog = 0xF75F, // fa-smog
	Smoking = 0xF48D, // fa-smoking
	Snowflake = 0xF2DC, // fa-snowflake
	Snowman = 0xF7D0, // fa-snowman
	Snowplow = 0xF7D2, // fa-snowplow
	Soap = 0xE06E, // fa-soap
	Socks = 0xF696, // fa-socks
	SolarPanel = 0xF5BA, // fa-solar-panel
	Sort = 0xF0DC, // fa-sort
	SortDown = 0xF0DD, // fa-sort-down
	SortUp = 0xF0DE, // fa-sort-up
	Spa = 0xF5BB, // fa-spa
	SpaghettiMonsterFlying = 0xF67B, // fa-spaghetti-monster-flying
	SpellCheck = 0xF891, // fa-spell-check
	Spider = 0xF717, // fa-spider
	Spinner = 0xF110, // fa-spinner
	Splotch = 0xF5BC, // fa-splotch
	Spoon = 0xF2E5, // fa-spoon
	SprayCan = 0xF5BD, // fa-spray-can
	SprayCanSparkles = 0xF5D0, // fa-spray-can-sparkles
	Square = 0xF0C8, // fa-square
	SquareArrowUpRight = 0xF14C, // fa-square-arrow-up-right
	SquareBinary = 0xE69B, // fa-square-binary
	SquareCaretDown = 0xF150, // fa-square-caret-down
	SquareCaretLeft = 0xF191, // fa-square-caret-left
	SquareCaretRight = 0xF152, // fa-square-caret-right
	SquareCaretUp = 0xF151, // fa-square-caret-up
	SquareCheck = 0xF14A, // fa-square-check
	SquareEnvelope = 0xF199, // fa-square-envelope
	SquareFull = 0xF45C, // fa-square-full
	SquareH = 0xF0FD, // fa-square-h
	SquareMinus = 0xF146, // fa-square-minus
	SquareNfi = 0xE576, // fa-square-nfi
	SquareParking = 0xF540, // fa-square-parking
	SquarePen = 0xF14B, // fa-square-pen
	SquarePersonConfined = 0xE577, // fa-square-person-confined
	SquarePhone = 0xF098, // fa-square-phone
	SquarePhoneFlip = 0xF87B, // fa-square-phone-flip
	SquarePlus = 0xF0FE, // fa-square-plus
	SquarePollHorizontal = 0xF682, // fa-square-poll-horizontal
	SquarePollVertical = 0xF681, // fa-square-poll-vertical
	SquareRootVariable = 0xF698, // fa-square-root-variable
	SquareRss = 0xF143, // fa-square-rss
	SquareShareNodes = 0xF1E1, // fa-square-share-nodes
	SquareUpRight = 0xF360, // fa-square-up-right
	SquareVirus = 0xE578, // fa-square-virus
	SquareXmark = 0xF2D3, // fa-square-xmark
	StaffSnake = 0xE579, // fa-staff-snake
	Stairs = 0xE289, // fa-stairs
	Stamp = 0xF5BF, // fa-stamp
	Stapler = 0xE5AF, // fa-stapler
	Star = 0xF005, // fa-star
	StarAndCrescent = 0xF699, // fa-star-and-crescent
	StarHalf = 0xF089, // fa-star-half
	StarHalfStroke = 0xF5C0, // fa-star-half-stroke
	StarOfDavid = 0xF69A, // fa-star-of-david
	StarOfLife = 0xF621, // fa-star-of-life
	SterlingSign = 0xF154, // fa-sterling-sign
	Stethoscope = 0xF0F1, // fa-stethoscope
	Stop = 0xF04D, // fa-stop
	Stopwatch = 0xF2F2, // fa-stopwatch
	Stopwatch20 = 0xE06F, // fa-stopwatch-20
	Store = 0xF54E, // fa-store
	StoreSlash = 0xE071, // fa-store-slash
	StreetView = 0xF21D, // fa-street-view
	Strikethrough = 0xF0CC, // fa-strikethrough
	Stroopwafel = 0xF551, // fa-stroopwafel
	Subscript = 0xF12C, // fa-subscript
	Suitcase = 0xF0F2, // fa-suitcase
	SuitcaseMedical = 0xF0FA, // fa-suitcase-medical
	SuitcaseRolling = 0xF5C1, // fa-suitcase-rolling
	Sun = 0xF185, // fa-sun
	SunPlantWilt = 0xE57A, // fa-sun-plant-wilt
	Superscript = 0xF12B, // fa-superscript
	Swatchbook = 0xF5C3, // fa-swatchbook
	Synagogue = 0xF69B, // fa-synagogue
	Syringe = 0xF48E, // fa-syringe
	T = 0x54, // fa-t
	Table = 0xF0CE, // fa-table
	TableCells = 0xF00A, // fa-table-cells
	TableCellsColumnLock = 0xE678, // fa-table-cells-column-lock
	TableCellsLarge = 0xF009, // fa-table-cells-large
	TableCellsRowLock = 0xE67A, // fa-table-cells-row-lock
	TableCellsRowUnlock = 0xE691, // fa-table-cells-row-unlock
	TableColumns = 0xF0DB, // fa-table-columns
	TableList = 0xF00B, // fa-table-list
	TableTennisPaddleBall = 0xF45D, // fa-table-tennis-paddle-ball
	Tablet = 0xF3FB, // fa-tablet
	TabletButton = 0xF10A, // fa-tablet-button
	TabletScreenButton = 0xF3FA, // fa-tablet-screen-button
	Tablets = 0xF490, // fa-tablets
	TachographDigital = 0xF566, // fa-tachograph-digital
	Tag = 0xF02B, // fa-tag
	Tags = 0xF02C, // fa-tags
	Tape = 0xF4DB, // fa-tape
	Tarp = 0xE57B, // fa-tarp
	TarpDroplet = 0xE57C, // fa-tarp-droplet
	Taxi = 0xF1BA, // fa-taxi
	Teeth = 0xF62E, // fa-teeth
	TeethOpen = 0xF62F, // fa-teeth-open
	TemperatureArrowDown = 0xE03F, // fa-temperature-arrow-down
	TemperatureArrowUp = 0xE040, // fa-temperature-arrow-up
	TemperatureEmpty = 0xF2CB, // fa-temperature-empty
	TemperatureFull = 0xF2C7, // fa-temperature-full
	TemperatureHalf = 0xF2C9, // fa-temperature-half
	TemperatureHigh = 0xF769, // fa-temperature-high
	TemperatureLow = 0xF76B, // fa-temperature-low
	TemperatureQuarter = 0xF2CA, // fa-temperature-quarter
	TemperatureThreeQuarters = 0xF2C8, // fa-temperature-three-quarters
	TengeSign = 0xF7D7, // fa-tenge-sign
	Tent = 0xE57D, // fa-tent
	TentArrowDownToLine = 0xE57E, // fa-tent-arrow-down-to-line
	TentArrowLeftRight = 0xE57F, // fa-tent-arrow-left-right
	TentArrowTurnLeft = 0xE580, // fa-tent-arrow-turn-left
	TentArrowsDown = 0xE581, // fa-tent-arrows-down
	Tents = 0xE582, // fa-tents
	Terminal = 0xF120, // fa-terminal
	TextHeight = 0xF034, // fa-text-height
	TextSlash = 0xF87D, // fa-text-slash
	TextWidth = 0xF035, // fa-text-width
	Thermometer = 0xF491, // fa-thermometer
	ThumbsDown = 0xF165, // fa-thumbs-down
	ThumbsUp = 0xF164, // fa-thumbs-up
	Thumbtack = 0xF08D, // fa-thumbtack
	ThumbtackSlash = 0xE68F, // fa-thumbtack-slash
	Ticket = 0xF145, // fa-ticket
	TicketSimple = 0xF3FF, // fa-ticket-simple
	Timeline = 0xE29C, // fa-timeline
	ToggleOff = 0xF204, // fa-toggle-off
	ToggleOn = 0xF205, // fa-toggle-on
	Toilet = 0xF7D8, // fa-toilet
	ToiletPaper = 0xF71E, // fa-toilet-paper
	ToiletPaperSlash = 0xE072, // fa-toilet-paper-slash
	ToiletPortable = 0xE583, // fa-toilet-portable
	ToiletsPortable = 0xE584, // fa-toilets-portable
	Toolbox = 0xF552, // fa-toolbox
	Tooth = 0xF5C9, // fa-tooth
	ToriiGate = 0xF6A1, // fa-torii-gate
	Tornado = 0xF76F, // fa-tornado
	TowerBroadcast = 0xF519, // fa-tower-broadcast
	TowerCell = 0xE585, // fa-tower-cell
	TowerObservation = 0xE586, // fa-tower-observation
	Tractor = 0xF722, // fa-tractor
	Trademark = 0xF25C, // fa-trademark
	TrafficLight = 0xF637, // fa-traffic-light
	Trailer = 0xE041, // fa-trailer
	Train = 0xF238, // fa-train
	TrainSubway = 0xF239, // fa-train-subway
	TrainTram = 0xE5B4, // fa-train-tram
	Transgender = 0xF225, // fa-transgender
	Trash = 0xF1F8, // fa-trash
	TrashArrowUp = 0xF829, // fa-trash-arrow-up
	TrashCan = 0xF2ED, // fa-trash-can
	TrashCanArrowUp = 0xF82A, // fa-trash-can-arrow-up
	Tree = 0xF1BB, // fa-tree
	TreeCity = 0xE587, // fa-tree-city
	TriangleExclamation = 0xF071, // fa-triangle-exclamation
	Trophy = 0xF091, // fa-trophy
	Trowel = 0xE589, // fa-trowel
	TrowelBricks = 0xE58A, // fa-trowel-bricks
	Truck = 0xF0D1, // fa-truck
	TruckArrowRight = 0xE58B, // fa-truck-arrow-right
	TruckDroplet = 0xE58C, // fa-truck-droplet
	TruckFast = 0xF48B, // fa-truck-fast
	TruckField = 0xE58D, // fa-truck-field
	TruckFieldUn = 0xE58E, // fa-truck-field-un
	TruckFront = 0xE2B7, // fa-truck-front
	TruckMedical = 0xF0F9, // fa-truck-medical
	TruckMonster = 0xF63B, // fa-truck-monster
	TruckMoving = 0xF4DF, // fa-truck-moving
	TruckPickup = 0xF63C, // fa-truck-pickup
	TruckPlane = 0xE58F, // fa-truck-plane
	TruckRampBox = 0xF4DE, // fa-truck-ramp-box
	Tty = 0xF1E4, // fa-tty
	TurkishLiraSign = 0xE2BB, // fa-turkish-lira-sign
	TurnDown = 0xF3BE, // fa-turn-down
	TurnUp = 0xF3BF, // fa-turn-up
	Tv = 0xF26C, // fa-tv
	U = 0x55, // fa-u
	Umbrella = 0xF0E9, // fa-umbrella
	UmbrellaBeach = 0xF5CA, // fa-umbrella-beach
	Underline = 0xF0CD, // fa-underline
	UniversalAccess = 0xF29A, // fa-universal-access
	Unlock = 0xF09C, // fa-unlock
	UnlockKeyhole = 0xF13E, // fa-unlock-keyhole
	UpDown = 0xF338, // fa-up-down
	UpDownLeftRight = 0xF0B2, // fa-up-down-left-right
	UpLong = 0xF30C, // fa-up-long
	UpRightAndDownLeftFromCenter = 0xF424, // fa-up-right-and-down-left-from-center
	UpRightFromSquare = 0xF35D, // fa-up-right-from-square
	Upload = 0xF093, // fa-upload
	User = 0xF007, // fa-user
	UserAstronaut = 0xF4FB, // fa-user-astronaut
	UserCheck = 0xF4FC, // fa-user-check
	UserClock = 0xF4FD, // fa-user-clock
	UserDoctor = 0xF0F0, // fa-user-doctor
	UserGear = 0xF4FE, // fa-user-gear
	UserGraduate = 0xF501, // fa-user-graduate
	UserGroup = 0xF500, // fa-user-group
	UserInjured = 0xF728, // fa-user-injured
	UserLarge = 0xF406, // fa-user-large
	UserLargeSlash = 0xF4FA, // fa-user-large-slash
	UserLock = 0xF502, // fa-user-lock
	UserMinus = 0xF503, // fa-user-minus
	UserNinja = 0xF504, // fa-user-ninja
	UserNurse = 0xF82F, // fa-user-nurse
	UserPen = 0xF4FF, // fa-user-pen
	UserPlus = 0xF234, // fa-user-plus
	UserSecret = 0xF21B, // fa-user-secret
	UserShield = 0xF505, // fa-user-shield
	UserSlash = 0xF506, // fa-user-slash
	UserTag = 0xF507, // fa-user-tag
	UserTie = 0xF508, // fa-user-tie
	UserXmark = 0xF235, // fa-user-xmark
	Users = 0xF0C0, // fa-users
	UsersBetweenLines = 0xE591, // fa-users-between-lines
	UsersGear = 0xF509, // fa-users-gear
	UsersLine = 0xE592, // fa-users-line
	UsersRays = 0xE593, // fa-users-rays
	UsersRectangle = 0xE594, // fa-users-rectangle
	UsersSlash = 0xE073, // fa-users-slash
	UsersViewfinder = 0xE595, // fa-users-viewfinder
	Utensils = 0xF2E7, // fa-utensils
	V = 0x56, // fa-v
	VanShuttle = 0xF5B6, // fa-van-shuttle
	Vault = 0xE2C5, // fa-vault
	VectorSquare = 0xF5CB, // fa-vector-square
	Venus = 0xF221, // fa-venus
	VenusDouble = 0xF226, // fa-venus-double
	VenusMars = 0xF228, // fa-venus-mars
	Vest = 0xE085, // fa-vest
	VestPatches = 0xE086, // fa-vest-patches
	Vial = 0xF492, // fa-vial
	VialCircleCheck = 0xE596, // fa-vial-circle-check
	VialVirus = 0xE597, // fa-vial-virus
	Vials = 0xF493, // fa-vials
	Video = 0xF03D, // fa-video
	VideoSlash = 0xF4E2, // fa-video-slash
	Vihara = 0xF6A7, // fa-vihara
	Virus = 0xE074, // fa-virus
	VirusCovid = 0xE4A8, // fa-virus-covid
	VirusCovidSlash = 0xE4A9, // fa-virus-covid-slash
	VirusSlash = 0xE075, // fa-virus-slash
	Viruses = 0xE076, // fa-viruses
	Voicemail = 0xF897, // fa-voicemail
	Volcano = 0xF770, // fa-volcano
	Volleyball = 0xF45F, // fa-volleyball
	VolumeHigh = 0xF028, // fa-volume-high
	VolumeLow = 0xF027, // fa-volume-low
	VolumeOff = 0xF026, // fa-volume-off
	VolumeXmark = 0xF6A9, // fa-volume-xmark
	VrCardboard = 0xF729, // fa-vr-cardboard
	W = 0x57, // fa-w
	WalkieTalkie = 0xF8EF, // fa-walkie-talkie
	Wallet = 0xF555, // fa-wallet
	WandMagic = 0xF0D0, // fa-wand-magic
	WandMagicSparkles = 0xE2CA, // fa-wand-magic-sparkles
	WandSparkles = 0xF72B, // fa-wand-sparkles
	Warehouse = 0xF494, // fa-warehouse
	Water = 0xF773, // fa-water
	WaterLadder = 0xF5C5, // fa-water-ladder
	WaveSquare = 0xF83E, // fa-wave-square
	WebAwesome = 0xE682, // fa-web-awesome
	WeightHanging = 0xF5CD, // fa-weight-hanging
	WeightScale = 0xF496, // fa-weight-scale
	WheatAwn = 0xE2CD, // fa-wheat-awn
	WheatAwnCircleExclamation = 0xE598, // fa-wheat-awn-circle-exclamation
	Wheelchair = 0xF193, // fa-wheelchair
	WheelchairMove = 0xE2CE, // fa-wheelchair-move
	WhiskeyGlass = 0xF7A0, // fa-whiskey-glass
	Wifi = 0xF1EB, // fa-wifi
	Wind = 0xF72E, // fa-wind
	WindowMaximize = 0xF2D0, // fa-window-maximize
	WindowMinimize = 0xF2D1, // fa-window-minimize
	WindowRestore = 0xF2D2, // fa-window-restore
	WineBottle = 0xF72F, // fa-wine-bottle
	WineGlass = 0xF4E3, // fa-wine-glass
	WineGlassEmpty = 0xF5CE, // fa-wine-glass-empty
	WonSign = 0xF159, // fa-won-sign
	Worm = 0xE599, // fa-worm
	Wrench = 0xF0AD, // fa-wrench
	X = 0x58, // fa-x
	XRay = 0xF497, // fa-x-ray
	Xmark = 0xF00D, // fa-xmark
	XmarksLines = 0xE59A, // fa-xmarks-lines
	Y = 0x59, // fa-y
	YenSign = 0xF157, // fa-yen-sign
	YinYang = 0xF6AD, // fa-yin-yang
	Z = 0x5A, // fa-z
	Search = 0xF002, // fa-magnifying-glass
	Save = 0xF0C7, // fa-floppy-disk
	Settings = 0xF013, // fa-gear
	Cog = 0xF013, // fa-gear
	Home = 0xF015, // fa-house
	Edit = 0xF044, // fa-pen-to-square
	Close = 0xF00D, // fa-xmark
	Cancel = 0xF00D, // fa-xmark
	Refresh = 0xF021, // fa-arrows-rotate
	Warning = 0xF071, // fa-triangle-exclamation
	CheckCircle = 0xF058, // fa-circle-check
	TimesCircle = 0xF057, // fa-circle-xmark
	VolumeMute = 0xF6A9, // fa-volume-xmark
	Cut = 0xF0C4, // fa-scissors
	Undo = 0xF2EA, // fa-arrow-rotate-left
	Redo = 0xF01E, // fa-arrow-rotate-right
	StepForward = 0xF051, // fa-forward-step
	StepBackward = 0xF048, // fa-backward-step
	Pin = 0xF08D, // fa-thumbtack
	ZoomIn = 0xF00E, // fa-magnifying-glass-plus
	ZoomOut = 0xF010, // fa-magnifying-glass-minus
}

// ============================================================================
// Precomputed Codepoint Atlas for Raylib TrueType Rasterizer
// ============================================================================
ALL_ICON_CODEPOINTS := []rune{
	0x21, 0x23, 0x24, 0x25, 0x2A, 0x2B, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35,
	0x36, 0x37, 0x38, 0x39, 0x3C, 0x3D, 0x3E, 0x3F, 0x40, 0x41, 0x42, 0x43,
	0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F,
	0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0xE005,
	0xE006, 0xE00D, 0xE012, 0xE03F, 0xE040, 0xE041, 0xE059, 0xE05A, 0xE05B, 0xE05C, 0xE05D, 0xE05E,
	0xE05F, 0xE060, 0xE061, 0xE062, 0xE063, 0xE064, 0xE065, 0xE066, 0xE067, 0xE068, 0xE069, 0xE06A,
	0xE06B, 0xE06C, 0xE06D, 0xE06E, 0xE06F, 0xE070, 0xE071, 0xE072, 0xE073, 0xE074, 0xE075, 0xE076,
	0xE085, 0xE086, 0xE097, 0xE098, 0xE09A, 0xE0A9, 0xE0AC, 0xE0B4, 0xE0B7, 0xE0BB, 0xE0D8, 0xE0DF,
	0xE0E3, 0xE0E4, 0xE131, 0xE139, 0xE13A, 0xE13B, 0xE13C, 0xE140, 0xE152, 0xE163, 0xE169, 0xE16D,
	0xE17B, 0xE184, 0xE185, 0xE18F, 0xE19A, 0xE19B, 0xE1A8, 0xE1B0, 0xE1BC, 0xE1C4, 0xE1C8, 0xE1D3,
	0xE1D5, 0xE1D7, 0xE1ED, 0xE1F3, 0xE1F6, 0xE1FE, 0xE209, 0xE221, 0xE222, 0xE22D, 0xE23D, 0xE289,
	0xE29C, 0xE2B7, 0xE2BB, 0xE2C5, 0xE2CA, 0xE2CD, 0xE2CE, 0xE2E6, 0xE2EB, 0xE31E, 0xE3AF, 0xE3B1,
	0xE3B2, 0xE3F5, 0xE43C, 0xE445, 0xE447, 0xE448, 0xE46C, 0xE473, 0xE476, 0xE477, 0xE47A, 0xE47B,
	0xE490, 0xE494, 0xE4A5, 0xE4A8, 0xE4A9, 0xE4AA, 0xE4AB, 0xE4AC, 0xE4AD, 0xE4AF, 0xE4B0, 0xE4B3,
	0xE4B5, 0xE4B6, 0xE4B7, 0xE4B8, 0xE4B9, 0xE4BA, 0xE4BB, 0xE4BC, 0xE4BD, 0xE4BE, 0xE4BF, 0xE4C0,
	0xE4C1, 0xE4C2, 0xE4C3, 0xE4C4, 0xE4C5, 0xE4C6, 0xE4C7, 0xE4C8, 0xE4C9, 0xE4CA, 0xE4CB, 0xE4CC,
	0xE4CE, 0xE4CF, 0xE4D0, 0xE4D1, 0xE4D2, 0xE4D3, 0xE4D4, 0xE4D5, 0xE4D6, 0xE4D7, 0xE4D8, 0xE4D9,
	0xE4DA, 0xE4DB, 0xE4DC, 0xE4DD, 0xE4DE, 0xE4E0, 0xE4E1, 0xE4E2, 0xE4E3, 0xE4E4, 0xE4E5, 0xE4E6,
	0xE4E8, 0xE4E9, 0xE4EA, 0xE4EB, 0xE4ED, 0xE4EF, 0xE4F0, 0xE4F1, 0xE4F2, 0xE4F3, 0xE4F4, 0xE4F5,
	0xE4F6, 0xE4F7, 0xE4F8, 0xE4F9, 0xE4FA, 0xE4FB, 0xE4FC, 0xE4FD, 0xE4FE, 0xE4FF, 0xE500, 0xE501,
	0xE502, 0xE503, 0xE507, 0xE508, 0xE509, 0xE50A, 0xE50B, 0xE50C, 0xE50D, 0xE50E, 0xE50F, 0xE510,
	0xE511, 0xE512, 0xE513, 0xE514, 0xE515, 0xE516, 0xE517, 0xE518, 0xE519, 0xE51A, 0xE51B, 0xE51C,
	0xE51D, 0xE51E, 0xE51F, 0xE520, 0xE521, 0xE522, 0xE523, 0xE524, 0xE525, 0xE527, 0xE528, 0xE529,
	0xE52A, 0xE52B, 0xE52C, 0xE52D, 0xE52E, 0xE52F, 0xE532, 0xE533, 0xE534, 0xE535, 0xE536, 0xE537,
	0xE538, 0xE539, 0xE53A, 0xE53B, 0xE53C, 0xE53D, 0xE53E, 0xE53F, 0xE540, 0xE541, 0xE542, 0xE543,
	0xE544, 0xE545, 0xE546, 0xE547, 0xE548, 0xE549, 0xE54A, 0xE54B, 0xE54C, 0xE54D, 0xE54E, 0xE54F,
	0xE551, 0xE552, 0xE553, 0xE554, 0xE555, 0xE556, 0xE557, 0xE558, 0xE55A, 0xE55B, 0xE55C, 0xE55D,
	0xE55E, 0xE55F, 0xE560, 0xE561, 0xE562, 0xE563, 0xE564, 0xE565, 0xE566, 0xE567, 0xE568, 0xE569,
	0xE56A, 0xE56B, 0xE56C, 0xE56D, 0xE56E, 0xE56F, 0xE571, 0xE572, 0xE573, 0xE574, 0xE576, 0xE577,
	0xE578, 0xE579, 0xE57A, 0xE57B, 0xE57C, 0xE57D, 0xE57E, 0xE57F, 0xE580, 0xE581, 0xE582, 0xE583,
	0xE584, 0xE585, 0xE586, 0xE587, 0xE589, 0xE58A, 0xE58B, 0xE58C, 0xE58D, 0xE58E, 0xE58F, 0xE591,
	0xE592, 0xE593, 0xE594, 0xE595, 0xE596, 0xE597, 0xE598, 0xE599, 0xE59A, 0xE59C, 0xE59D, 0xE5A0,
	0xE5A1, 0xE5A9, 0xE5AA, 0xE5AF, 0xE5B4, 0xE678, 0xE67A, 0xE682, 0xE68F, 0xE691, 0xE695, 0xE696,
	0xE697, 0xE698, 0xE699, 0xE69A, 0xE69B, 0xF000, 0xF001, 0xF002, 0xF004, 0xF005, 0xF007, 0xF008,
	0xF009, 0xF00A, 0xF00B, 0xF00C, 0xF00D, 0xF00E, 0xF010, 0xF011, 0xF012, 0xF013, 0xF015, 0xF017,
	0xF018, 0xF019, 0xF01C, 0xF01E, 0xF021, 0xF022, 0xF023, 0xF024, 0xF025, 0xF026, 0xF027, 0xF028,
	0xF029, 0xF02A, 0xF02B, 0xF02C, 0xF02D, 0xF02E, 0xF02F, 0xF030, 0xF031, 0xF032, 0xF033, 0xF034,
	0xF035, 0xF036, 0xF037, 0xF038, 0xF039, 0xF03A, 0xF03B, 0xF03C, 0xF03D, 0xF03E, 0xF041, 0xF042,
	0xF043, 0xF044, 0xF047, 0xF048, 0xF049, 0xF04A, 0xF04B, 0xF04C, 0xF04D, 0xF04E, 0xF050, 0xF051,
	0xF052, 0xF053, 0xF054, 0xF055, 0xF056, 0xF057, 0xF058, 0xF059, 0xF05A, 0xF05B, 0xF05E, 0xF060,
	0xF061, 0xF062, 0xF063, 0xF064, 0xF065, 0xF066, 0xF068, 0xF06A, 0xF06B, 0xF06C, 0xF06D, 0xF06E,
	0xF070, 0xF071, 0xF072, 0xF073, 0xF074, 0xF075, 0xF076, 0xF077, 0xF078, 0xF079, 0xF07A, 0xF07B,
	0xF07C, 0xF07D, 0xF07E, 0xF080, 0xF083, 0xF084, 0xF085, 0xF086, 0xF089, 0xF08B, 0xF08D, 0xF08E,
	0xF090, 0xF091, 0xF093, 0xF094, 0xF095, 0xF098, 0xF09C, 0xF09D, 0xF09E, 0xF0A0, 0xF0A1, 0xF0A3,
	0xF0A4, 0xF0A5, 0xF0A6, 0xF0A7, 0xF0A8, 0xF0A9, 0xF0AA, 0xF0AB, 0xF0AC, 0xF0AD, 0xF0AE, 0xF0B0,
	0xF0B1, 0xF0B2, 0xF0C0, 0xF0C1, 0xF0C2, 0xF0C3, 0xF0C4, 0xF0C5, 0xF0C6, 0xF0C7, 0xF0C8, 0xF0C9,
	0xF0CA, 0xF0CB, 0xF0CC, 0xF0CD, 0xF0CE, 0xF0D0, 0xF0D1, 0xF0D6, 0xF0D7, 0xF0D8, 0xF0D9, 0xF0DA,
	0xF0DB, 0xF0DC, 0xF0DD, 0xF0DE, 0xF0E0, 0xF0E2, 0xF0E3, 0xF0E7, 0xF0E8, 0xF0E9, 0xF0EA, 0xF0EB,
	0xF0EC, 0xF0ED, 0xF0EE, 0xF0F0, 0xF0F1, 0xF0F2, 0xF0F3, 0xF0F4, 0xF0F8, 0xF0F9, 0xF0FA, 0xF0FB,
	0xF0FC, 0xF0FD, 0xF0FE, 0xF100, 0xF101, 0xF102, 0xF103, 0xF104, 0xF105, 0xF106, 0xF107, 0xF109,
	0xF10A, 0xF10B, 0xF10D, 0xF10E, 0xF110, 0xF111, 0xF118, 0xF119, 0xF11A, 0xF11B, 0xF11C, 0xF11E,
	0xF120, 0xF121, 0xF122, 0xF124, 0xF125, 0xF126, 0xF127, 0xF129, 0xF12B, 0xF12C, 0xF12D, 0xF12E,
	0xF130, 0xF131, 0xF132, 0xF133, 0xF134, 0xF135, 0xF137, 0xF138, 0xF139, 0xF13A, 0xF13D, 0xF13E,
	0xF140, 0xF141, 0xF142, 0xF143, 0xF144, 0xF145, 0xF146, 0xF148, 0xF149, 0xF14A, 0xF14B, 0xF14C,
	0xF14D, 0xF14E, 0xF150, 0xF151, 0xF152, 0xF153, 0xF154, 0xF156, 0xF157, 0xF158, 0xF159, 0xF15B,
	0xF15C, 0xF15D, 0xF15E, 0xF160, 0xF161, 0xF162, 0xF163, 0xF164, 0xF165, 0xF175, 0xF176, 0xF177,
	0xF178, 0xF182, 0xF183, 0xF185, 0xF186, 0xF187, 0xF188, 0xF191, 0xF192, 0xF193, 0xF195, 0xF197,
	0xF199, 0xF19C, 0xF19D, 0xF1AB, 0xF1AC, 0xF1AD, 0xF1AE, 0xF1B0, 0xF1B2, 0xF1B3, 0xF1B8, 0xF1B9,
	0xF1BA, 0xF1BB, 0xF1C0, 0xF1C1, 0xF1C2, 0xF1C3, 0xF1C4, 0xF1C5, 0xF1C6, 0xF1C7, 0xF1C8, 0xF1C9,
	0xF1CD, 0xF1CE, 0xF1D8, 0xF1DA, 0xF1DC, 0xF1DD, 0xF1DE, 0xF1E0, 0xF1E1, 0xF1E2, 0xF1E3, 0xF1E4,
	0xF1E5, 0xF1E6, 0xF1EA, 0xF1EB, 0xF1EC, 0xF1F6, 0xF1F8, 0xF1F9, 0xF1FB, 0xF1FC, 0xF1FD, 0xF1FE,
	0xF200, 0xF201, 0xF204, 0xF205, 0xF206, 0xF207, 0xF20A, 0xF20B, 0xF217, 0xF218, 0xF219, 0xF21A,
	0xF21B, 0xF21C, 0xF21D, 0xF21E, 0xF221, 0xF222, 0xF223, 0xF224, 0xF225, 0xF226, 0xF227, 0xF228,
	0xF229, 0xF22A, 0xF22B, 0xF22C, 0xF22D, 0xF233, 0xF234, 0xF235, 0xF236, 0xF238, 0xF239, 0xF240,
	0xF241, 0xF242, 0xF243, 0xF244, 0xF245, 0xF246, 0xF247, 0xF248, 0xF249, 0xF24D, 0xF24E, 0xF251,
	0xF252, 0xF253, 0xF254, 0xF255, 0xF256, 0xF257, 0xF258, 0xF259, 0xF25A, 0xF25B, 0xF25C, 0xF25D,
	0xF26C, 0xF271, 0xF272, 0xF273, 0xF274, 0xF275, 0xF276, 0xF277, 0xF279, 0xF27A, 0xF28B, 0xF28D,
	0xF290, 0xF291, 0xF29A, 0xF29D, 0xF29E, 0xF2A0, 0xF2A1, 0xF2A2, 0xF2A3, 0xF2A4, 0xF2A7, 0xF2A8,
	0xF2B4, 0xF2B5, 0xF2B6, 0xF2B9, 0xF2BB, 0xF2BD, 0xF2C1, 0xF2C2, 0xF2C7, 0xF2C8, 0xF2C9, 0xF2CA,
	0xF2CB, 0xF2CC, 0xF2CD, 0xF2CE, 0xF2D0, 0xF2D1, 0xF2D2, 0xF2D3, 0xF2DB, 0xF2DC, 0xF2E5, 0xF2E7,
	0xF2EA, 0xF2ED, 0xF2F1, 0xF2F2, 0xF2F5, 0xF2F6, 0xF2F9, 0xF2FE, 0xF302, 0xF303, 0xF304, 0xF305,
	0xF309, 0xF30A, 0xF30B, 0xF30C, 0xF31C, 0xF31E, 0xF328, 0xF337, 0xF338, 0xF358, 0xF359, 0xF35A,
	0xF35B, 0xF35D, 0xF360, 0xF362, 0xF363, 0xF386, 0xF387, 0xF390, 0xF3A5, 0xF3BE, 0xF3BF, 0xF3C1,
	0xF3C5, 0xF3C9, 0xF3CD, 0xF3CE, 0xF3CF, 0xF3D1, 0xF3DD, 0xF3E0, 0xF3E5, 0xF3ED, 0xF3FA, 0xF3FB,
	0xF3FF, 0xF406, 0xF410, 0xF422, 0xF424, 0xF432, 0xF433, 0xF434, 0xF436, 0xF439, 0xF43A, 0xF43C,
	0xF43F, 0xF441, 0xF443, 0xF445, 0xF447, 0xF44B, 0xF44E, 0xF450, 0xF453, 0xF458, 0xF45C, 0xF45D,
	0xF45F, 0xF461, 0xF462, 0xF466, 0xF468, 0xF469, 0xF46A, 0xF46B, 0xF46C, 0xF46D, 0xF470, 0xF471,
	0xF472, 0xF474, 0xF477, 0xF478, 0xF479, 0xF47E, 0xF47F, 0xF481, 0xF482, 0xF484, 0xF485, 0xF486,
	0xF487, 0xF48B, 0xF48D, 0xF48E, 0xF490, 0xF491, 0xF492, 0xF493, 0xF494, 0xF496, 0xF497, 0xF49E,
	0xF4AD, 0xF4B3, 0xF4B8, 0xF4B9, 0xF4BA, 0xF4BD, 0xF4BE, 0xF4C0, 0xF4C1, 0xF4C2, 0xF4C4, 0xF4C6,
	0xF4CD, 0xF4CE, 0xF4D3, 0xF4D6, 0xF4D7, 0xF4D8, 0xF4D9, 0xF4DA, 0xF4DB, 0xF4DE, 0xF4DF, 0xF4E2,
	0xF4E3, 0xF4FA, 0xF4FB, 0xF4FC, 0xF4FD, 0xF4FE, 0xF4FF, 0xF500, 0xF501, 0xF502, 0xF503, 0xF504,
	0xF505, 0xF506, 0xF507, 0xF508, 0xF509, 0xF515, 0xF516, 0xF517, 0xF518, 0xF519, 0xF51A, 0xF51B,
	0xF51C, 0xF51D, 0xF51E, 0xF51F, 0xF520, 0xF521, 0xF522, 0xF523, 0xF524, 0xF525, 0xF526, 0xF527,
	0xF528, 0xF529, 0xF52A, 0xF52B, 0xF52D, 0xF52E, 0xF52F, 0xF530, 0xF532, 0xF533, 0xF534, 0xF535,
	0xF537, 0xF538, 0xF539, 0xF53A, 0xF53B, 0xF53C, 0xF53D, 0xF53E, 0xF53F, 0xF540, 0xF542, 0xF543,
	0xF544, 0xF545, 0xF546, 0xF547, 0xF548, 0xF549, 0xF54A, 0xF54B, 0xF54C, 0xF54D, 0xF54E, 0xF54F,
	0xF550, 0xF551, 0xF552, 0xF553, 0xF554, 0xF555, 0xF556, 0xF557, 0xF558, 0xF559, 0xF55A, 0xF55B,
	0xF55C, 0xF55D, 0xF55E, 0xF55F, 0xF560, 0xF561, 0xF562, 0xF563, 0xF564, 0xF565, 0xF566, 0xF567,
	0xF568, 0xF569, 0xF56A, 0xF56B, 0xF56C, 0xF56D, 0xF56E, 0xF56F, 0xF570, 0xF571, 0xF572, 0xF573,
	0xF574, 0xF575, 0xF576, 0xF577, 0xF578, 0xF579, 0xF57A, 0xF57B, 0xF57C, 0xF57D, 0xF57E, 0xF57F,
	0xF580, 0xF581, 0xF582, 0xF583, 0xF584, 0xF585, 0xF586, 0xF587, 0xF588, 0xF589, 0xF58A, 0xF58B,
	0xF58C, 0xF58D, 0xF58E, 0xF58F, 0xF590, 0xF591, 0xF593, 0xF594, 0xF595, 0xF596, 0xF597, 0xF598,
	0xF599, 0xF59A, 0xF59B, 0xF59C, 0xF59D, 0xF59F, 0xF5A0, 0xF5A1, 0xF5A2, 0xF5A4, 0xF5A5, 0xF5A6,
	0xF5A7, 0xF5AA, 0xF5AB, 0xF5AC, 0xF5AD, 0xF5AE, 0xF5AF, 0xF5B0, 0xF5B1, 0xF5B3, 0xF5B4, 0xF5B6,
	0xF5B7, 0xF5B8, 0xF5BA, 0xF5BB, 0xF5BC, 0xF5BD, 0xF5BF, 0xF5C0, 0xF5C1, 0xF5C2, 0xF5C3, 0xF5C4,
	0xF5C5, 0xF5C7, 0xF5C8, 0xF5C9, 0xF5CA, 0xF5CB, 0xF5CD, 0xF5CE, 0xF5D0, 0xF5D1, 0xF5D2, 0xF5D7,
	0xF5DA, 0xF5DC, 0xF5DE, 0xF5DF, 0xF5E1, 0xF5E4, 0xF5E7, 0xF5EB, 0xF5EE, 0xF5FC, 0xF5FD, 0xF601,
	0xF604, 0xF610, 0xF613, 0xF619, 0xF61F, 0xF621, 0xF624, 0xF625, 0xF629, 0xF62A, 0xF62E, 0xF62F,
	0xF630, 0xF637, 0xF63B, 0xF63C, 0xF641, 0xF644, 0xF647, 0xF64A, 0xF64F, 0xF651, 0xF653, 0xF654,
	0xF655, 0xF658, 0xF65D, 0xF65E, 0xF662, 0xF664, 0xF665, 0xF666, 0xF669, 0xF66A, 0xF66B, 0xF66D,
	0xF66F, 0xF674, 0xF676, 0xF678, 0xF679, 0xF67B, 0xF67C, 0xF67F, 0xF681, 0xF682, 0xF683, 0xF684,
	0xF687, 0xF688, 0xF689, 0xF696, 0xF698, 0xF699, 0xF69A, 0xF69B, 0xF6A0, 0xF6A1, 0xF6A7, 0xF6A9,
	0xF6AD, 0xF6B6, 0xF6B7, 0xF6BB, 0xF6BE, 0xF6C0, 0xF6C3, 0xF6C4, 0xF6C8, 0xF6CF, 0xF6D1, 0xF6D3,
	0xF6D5, 0xF6D7, 0xF6D9, 0xF6DD, 0xF6DE, 0xF6E2, 0xF6E3, 0xF6E6, 0xF6E8, 0xF6EC, 0xF6ED, 0xF6F0,
	0xF6F1, 0xF6F2, 0xF6FA, 0xF6FC, 0xF6FF, 0xF700, 0xF70B, 0xF70C, 0xF70E, 0xF714, 0xF715, 0xF717,
	0xF71E, 0xF722, 0xF728, 0xF729, 0xF72B, 0xF72E, 0xF72F, 0xF73B, 0xF73C, 0xF73D, 0xF740, 0xF743,
	0xF747, 0xF74D, 0xF751, 0xF752, 0xF753, 0xF756, 0xF75A, 0xF75B, 0xF75E, 0xF75F, 0xF769, 0xF76B,
	0xF76C, 0xF76F, 0xF770, 0xF772, 0xF773, 0xF77C, 0xF77D, 0xF780, 0xF781, 0xF783, 0xF784, 0xF786,
	0xF787, 0xF788, 0xF78C, 0xF793, 0xF794, 0xF796, 0xF79C, 0xF79F, 0xF7A0, 0xF7A2, 0xF7A4, 0xF7A5,
	0xF7A6, 0xF7A9, 0xF7AA, 0xF7AB, 0xF7AD, 0xF7AE, 0xF7B5, 0xF7B6, 0xF7B9, 0xF7BA, 0xF7BD, 0xF7BF,
	0xF7C0, 0xF7C2, 0xF7C4, 0xF7C5, 0xF7C9, 0xF7CA, 0xF7CC, 0xF7CD, 0xF7CE, 0xF7D0, 0xF7D2, 0xF7D7,
	0xF7D8, 0xF7D9, 0xF7DA, 0xF7E4, 0xF7E5, 0xF7E6, 0xF7EC, 0xF7EF, 0xF7F2, 0xF7F3, 0xF7F5, 0xF7F7,
	0xF7FA, 0xF7FB, 0xF802, 0xF805, 0xF806, 0xF807, 0xF80D, 0xF80F, 0xF810, 0xF812, 0xF815, 0xF816,
	0xF818, 0xF81D, 0xF827, 0xF828, 0xF829, 0xF82A, 0xF82F, 0xF83E, 0xF84A, 0xF84C, 0xF850, 0xF853,
	0xF85E, 0xF863, 0xF86D, 0xF879, 0xF87B, 0xF87C, 0xF87D, 0xF881, 0xF882, 0xF884, 0xF885, 0xF886,
	0xF887, 0xF891, 0xF897, 0xF8C0, 0xF8C1, 0xF8CC, 0xF8D7, 0xF8D9, 0xF8EF, 0xF8FF,
}

// ============================================================================
// Font Awesome Icon Cache & High-DPI Glyph Pipeline
// ============================================================================
iconFontsBySize: [MAX_CACHED_FONT_SIZE + 1]rl.Font

InitIconFonts :: proc() -> rl.Font {
	if !rl.IsWindowReady() do return {}
	standardSizes := []f32{14, 16, 18, 20, 24, 28, 32}
	for sz in standardSizes {
		_ = GetIconFont(sz)
	}
	return GetIconFont(DEFAULT_ICON_SIZE)
}

UnloadIconFonts :: proc() {
	if !rl.IsWindowReady() do return
	for i in MIN_CACHED_FONT_SIZE..=MAX_CACHED_FONT_SIZE {
		if iconFontsBySize[i].baseSize > 0 {
			rl.UnloadFont(iconFontsBySize[i])
			iconFontsBySize[i] = {}
		}
	}
}

GetIconFont :: proc(size: f32) -> rl.Font {
	if !rl.IsWindowReady() do return {}
	sz := size if size > 0 else DEFAULT_ICON_SIZE
	pxSize := clamp(i32(math.round(sz)), MIN_CACHED_FONT_SIZE, MAX_CACHED_FONT_SIZE)
	if iconFontsBySize[pxSize].baseSize > 0 {
		return iconFontsBySize[pxSize]
	}
	font := rl.LoadFontFromMemory(
		".ttf",
		raw_data(FA_SOLID_TTF),
		i32(len(FA_SOLID_TTF)),
		pxSize,
		raw_data(ALL_ICON_CODEPOINTS),
		i32(len(ALL_ICON_CODEPOINTS)),
	)
	if font.baseSize > 0 && font.texture.id > 0 {
		rl.SetTextureFilter(font.texture, .BILINEAR)
		iconFontsBySize[pxSize] = font
		return font
	}
	return {}
}

Icon_ToRune :: proc(icon: Icon) -> rune {
	return rune(icon)
}

Icon_ToString :: proc(icon: Icon, allocator := context.temp_allocator) -> string {
	if icon == .None do return ""
	buf, n := utf8.encode_rune(rune(icon))
	return strings.clone(string(buf[:n]), allocator)
}

Icon_ToCString :: proc(icon: Icon, allocator := context.temp_allocator) -> cstring {
	if icon == .None do return ""
	buf, n := utf8.encode_rune(rune(icon))
	return strings.clone_to_cstring(string(buf[:n]), allocator)
}

MeasureIcon :: proc(icon: Icon, size: f32 = DEFAULT_ICON_SIZE) -> [2]f32 {
	if icon == .None do return {0, 0}
	font := GetIconFont(size)
	if font.baseSize == 0 do return {size, size}
	buf, n := utf8.encode_rune(rune(icon))
	cstr := strings.clone_to_cstring(string(buf[:n]), context.temp_allocator)
	m := rl.MeasureTextEx(font, cstr, size, 0.0)
	return {m.x, m.y}
}

DrawIcon :: proc(icon: Icon, x, y: f32, size: f32 = DEFAULT_ICON_SIZE, color: rl.Color = {238, 240, 246, 255}) {
	if icon == .None || !rl.IsWindowReady() do return
	font := GetIconFont(size)
	if font.baseSize == 0 do return
	buf, n := utf8.encode_rune(rune(icon))
	cstr := strings.clone_to_cstring(string(buf[:n]), context.temp_allocator)
	rx := math.round(x)
	ry := math.round(y)
	rl.DrawTextEx(font, cstr, {rx, ry}, size, 0.0, color)
}

DrawIconCentered :: proc(icon: Icon, center: [2]f32, size: f32 = DEFAULT_ICON_SIZE, color: rl.Color = {238, 240, 246, 255}) {
	if icon == .None || !rl.IsWindowReady() do return
	m := MeasureIcon(icon, size)
	DrawIcon(icon, center.x - m.x * 0.5, center.y - m.y * 0.5, size, color)
}

RenderIcon :: proc(
	rect: rl.Rectangle,
	icon: Icon,
	size: f32 = 0,
	color: rl.Color = {238, 240, 246, 255},
	align: TextAlign = .Center,
) {
	if icon == .None || !rl.IsWindowReady() do return
	actualSize := size if size > 0 else min(rect.width, rect.height) * 0.70
	m := MeasureIcon(icon, actualSize)
	x := rect.x
	switch align {
	case .Left:
		x = rect.x
	case .Center:
		x = rect.x + (rect.width - m.x) * 0.5
	case .Right:
		x = rect.x + rect.width - m.x
	}
	y := rect.y + (rect.height - m.y) * 0.5
	DrawIcon(icon, x, y, actualSize, color)
}

// ============================================================================
// Immediate-Mode GuiIcon Widget
// ============================================================================
GuiIcon :: proc(
	rect: rl.Rectangle,
	icon: Icon,
	size: f32 = 0,
	color: rl.Color = {238, 240, 246, 255},
	align: TextAlign = .Center,
) {
	RenderIcon(rect, icon, size, color, align)
}
