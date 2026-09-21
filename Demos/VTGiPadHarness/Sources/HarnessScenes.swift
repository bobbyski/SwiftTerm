import Foundation

/// The VTG the harness feeds its terminal view.
///
/// Written as escape sequences rather than SDK calls on purpose: this is the
/// wire protocol a remote program would send, so anything that works here
/// works over SSH later, when there is an SSH.
enum HarnessScenes {
    /// `ESC _ VTG; <command> ESC \`
    static func vtg(_ command: String) -> String {
        "\u{1b}_VTG;\(command)\u{1b}\\"
    }

    /// One attributed-text run: `<style>:<utf-8 byte count>:<text>`.
    static func run(_ style: String, _ text: String) -> String {
        "\(style):\(text.utf8.count):\(text)"
    }

    /// Leave page mode, clear the scene and the screen.
    ///
    /// Sent before each scene so switching between them cannot accumulate
    /// state — the same reset a host performs when a program exits.
    /// `[3J` clears the scrollback as well as the screen. Without it the
    /// keyboard appearing resizes the terminal, and the reflow pulls the
    /// previous tab's lines back out of the scrollback and onto the screen.
    static let reset = vtg("pageEnd") + vtg("clear") + "\u{1b}[2J\u{1b}[3J\u{1b}[H"

    static let styles =
        vtg("textStyle,id=title,font=Georgia,size=40,weight=bold,color=#ffffff")
        + vtg("textStyle,id=body,font=Helvetica Neue,size=18,color=#cbd5e1")
        + vtg("textStyle,id=em,inherit=body,color=#5eead4,weight=bold")
        + vtg("textStyle,id=code,font=mono,size=15,color=#fbbf24")

    /// Plain terminal output: the baseline that must keep working.
    static let text = [
        "\u{1b}[1mSwiftTerm on iPadOS\u{1b}[0m",
        "",
        "This is the ordinary terminal, fed bytes by the app. There is no",
        "process behind it — iOS does not allow one — so every byte arrived",
        "through \u{1b}[36mfeed(byteArray:)\u{1b}[0m.",
        "",
        "\u{1b}[2mColours, attributes and the cursor work as they always did.\u{1b}[0m",
        "\u{1b}[31mred\u{1b}[0m \u{1b}[32mgreen\u{1b}[0m \u{1b}[33myellow\u{1b}[0m \u{1b}[34mblue\u{1b}[0m \u{1b}[35mmagenta\u{1b}[0m \u{1b}[36mcyan\u{1b}[0m",
        "",
        "Pick another tab to draw VTG graphics over this text.",
        ""
    // A bare "\n" is a line feed with no carriage return: the next line would
    // start where this one ended, in a staircase. Terminals want both.
    ].joined(separator: "\r\n")

    /// Retained VTG primitives in the overlay, over live terminal text.
    static let graphics =
        "\u{1b}[1mVTG graphics, drawn by the UIKit overlay\u{1b}[0m\r\n\r\n"
        + "The shapes below are retained primitives, not characters.\r\n"
        + "They are drawn by VTGOverlayView through Core Graphics —\r\n"
        + "the same code that draws them on the Mac.\r\n"
        + styles
        // Ask for taps. On iOS a tap arrives as a VTG click, the reply goes
        // to vtgResponseHandler, and the harness prints it.
        + vtg("mouseEvents,enabled=1,mode=click")
        + vtg("rect,id=panel,x=60,y=220,w=520,h=300,stroke=#5eead4,fill=#0b122099,width=2,radius=16")
        + vtg("circle,id=moon,cx=470,cy=300,r=44,stroke=none,fill=#f8fafc")
        + vtg("circle,id=shade,cx=492,cy=288,r=40,stroke=none,fill=#0b1220")
        + vtg("path,id=hill,d=M 60 470 L 200 360 L 320 440 L 430 370 L 580 470 Z,stroke=none,fill=#1c2458")
        + vtg("styledText,id=t,x=320,y=260,style=title,align=center;Vector graphics")
        + vtg("attrText,id=s,x=320,y=330,style=body,align=center;"
              + run("-", "Every primitive is retained and ")
              + run("em", "addressable by id")
              + run("-", "."))
        + vtg("styledText,id=c,x=320,y=430,style=code,align=center;rect · circle · path · styledText")

    /// A page: the whole of VTG Page Mode, on a tablet.
    static let page =
        "\u{1b}[2mOrdinary terminal output, underneath the page.\u{1b}[0m\r\n"
        + styles
        + vtg("pageBegin,id=harness")
        + vtg("pageOpen,id=card,bg=#0b1220f2,w=620,h=320,grow=none")
        + vtg("pageViewport,x=60,y=180,w=620,h=320")
        + vtg("rect,id=frame,x=1,y=1,w=618,h=318,stroke=#5eead4,fill=none,width=2,radius=14")
        + vtg("styledText,id=t,x=310,y=40,style=title,align=center;Page Mode")
        + vtg("attrText,id=s,x=310,y=120,style=body,align=center;"
              + run("-", "This page was built ")
              + run("em", "off screen")
              + run("-", ", then shown in one step.")
              + run("NL", "")
              + run("-", "It floats above the terminal, which is")
              + run("NL", "")
              + run("-", "still there underneath."))
        + vtg("styledText,id=c,x=310,y=250,style=code,align=center;pageOpen → draw → pageShow")
        + vtg("pageShow")

    /// The graphics scene with no terminal text in front of it, for the
    /// shell's `draw` command — the shell has already written its own.
    static var graphicsBody: String {
        styles
            + vtg("clear")
            + vtg("rect,id=panel,x=60,y=220,w=520,h=300,stroke=#5eead4,fill=#0b122099,width=2,radius=16")
            + vtg("circle,id=moon,cx=470,cy=300,r=44,stroke=none,fill=#f8fafc")
            + vtg("circle,id=shade,cx=492,cy=288,r=40,stroke=none,fill=#0b1220")
            + vtg("styledText,id=t,x=320,y=280,style=title,align=center;Drawn from a command")
            + vtg("styledText,id=c,x=320,y=430,style=code,align=center;draw · page · cls")
    }

    /// The page scene without its terminal line, for the shell's `page`.
    static var pageBody: String {
        styles
            + vtg("pageBegin,id=shell")
            + vtg("pageOpen,id=card,bg=#0b1220f2,w=620,h=300,grow=none")
            + vtg("pageViewport,x=60,y=200,w=620,h=300")
            + vtg("rect,id=frame,x=1,y=1,w=618,h=298,stroke=#5eead4,fill=none,width=2,radius=14")
            + vtg("styledText,id=t,x=310,y=40,style=title,align=center;Page Mode")
            + vtg("attrText,id=s,x=310,y=120,style=body,align=center;"
                  + run("-", "Opened by a command in the shell.")
                  + run("NL", "")
                  + run("-", "The next prompt takes it down, because the")
                  + run("NL", "")
                  + run("em", "shell emits OSC 133 prompt marks")
                  + run("-", "."))
            + vtg("pageShow")
    }
}
