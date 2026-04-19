import Foundation

enum TVKey: String {
    case power     = "KEY_POWER"
    case home      = "KEY_HOME"
    case menu      = "KEY_MENU"
    case source    = "KEY_SOURCE"
    case back      = "KEY_RETURN"
    case exit      = "KEY_EXIT"
    case tools     = "KEY_TOOLS"
    case info      = "KEY_INFO"
    case guide     = "KEY_GUIDE"

    case up        = "KEY_UP"
    case down      = "KEY_DOWN"
    case left      = "KEY_LEFT"
    case right     = "KEY_RIGHT"
    case enter     = "KEY_ENTER"

    case volumeUp   = "KEY_VOLUP"
    case volumeDown = "KEY_VOLDOWN"
    case mute       = "KEY_MUTE"
    case channelUp   = "KEY_CHUP"
    case channelDown = "KEY_CHDOWN"
    case channelList = "KEY_CH_LIST"

    case play   = "KEY_PLAY"
    case pause  = "KEY_PAUSE"
    case stop   = "KEY_STOP"
    case rewind = "KEY_REWIND"
    case fastForward = "KEY_FF"
    case record = "KEY_REC"

    case red    = "KEY_RED"
    case green  = "KEY_GREEN"
    case yellow = "KEY_YELLOW"
    case blue   = "KEY_BLUE"

    static func digit(_ n: Int) -> TVKey? {
        switch n {
        case 0: return .key0
        case 1: return .key1
        case 2: return .key2
        case 3: return .key3
        case 4: return .key4
        case 5: return .key5
        case 6: return .key6
        case 7: return .key7
        case 8: return .key8
        case 9: return .key9
        default: return nil
        }
    }

    case key0 = "KEY_0"
    case key1 = "KEY_1"
    case key2 = "KEY_2"
    case key3 = "KEY_3"
    case key4 = "KEY_4"
    case key5 = "KEY_5"
    case key6 = "KEY_6"
    case key7 = "KEY_7"
    case key8 = "KEY_8"
    case key9 = "KEY_9"
}
