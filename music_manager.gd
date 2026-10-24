extends Node
## Persistent background music controller for ASHEN.
## Menu: Batman track. Boss encounters: track selected by level index.

var _player: AudioStreamPlayer
var _current_track := ""

const MENU_TRACK := "res://audio/menu_batman.mp3"
const BOSS_TRACKS := [
    "res://audio/boss1_final_fantasy.mp3",
    "res://audio/boss2_deathevan.mp3",
    "res://audio/boss3_stronger_monsters.mp3"
]

func _ready() -> void:
    _player = AudioStreamPlayer.new()
    _player.name = "BackgroundMusicPlayer"
    _player.volume_db = -8.0
    add_child(_player)

func play_menu_music() -> void:
    _play_track(MENU_TRACK)

func play_boss_music(level_index: int) -> void:
    var index := clampi(level_index, 0, BOSS_TRACKS.size() - 1)
    _play_track(BOSS_TRACKS[index])

func stop_music() -> void:
    if _player:
        _player.stop()
        _current_track = ""

func _play_track(path: String) -> void:
    if _player == null:
        return
    if _current_track == path and _player.playing:
        return
    var stream := load(path) as AudioStreamMP3
    if stream == null:
        push_error("ASHEN music file could not be loaded: " + path)
        return
    stream.loop = true
    _player.stop()
    _player.stream = stream
    _player.play()
    _current_track = path
