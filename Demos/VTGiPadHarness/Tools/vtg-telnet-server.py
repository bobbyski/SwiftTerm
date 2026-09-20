#!/usr/bin/env python3
"""A tiny telnet server that draws, for testing the iPad harness's Remote tab.

    python3 Tools/vtg-telnet-server.py [port]     default: 2323

An iOS simulator reaches the host's loopback directly, so the harness
connecting to 127.0.0.1 on this port is talking to this process.

It negotiates like a real telnet server (asks for terminal type and window
size, offers to echo and to suppress go-ahead), echoes what you type, and
understands three commands — draw, page, cls — which send VTG. That is the
point: the graphics arrive over a socket, from a program that knows nothing
about iOS.
"""
import socket
import sys
import threading

IAC, DONT, DO, WONT, WILL, SB, SE = range(240, 256)[15:] and (255, 254, 253, 252, 251, 250, 240)
ECHO, SGA, TTYPE, NAWS = 1, 3, 24, 31


def vtg(command):
    return b"\x1b_VTG;" + command.encode() + b"\x1b\\"


DRAW = (
    vtg("textStyle,id=t,font=Georgia,size=36,weight=bold,color=#ffffff")
    + vtg("textStyle,id=c,font=mono,size=15,color=#fbbf24")
    + vtg("clear")
    + vtg("rect,id=panel,x=60,y=200,w=560,h=260,stroke=#38bdf8,fill=#082f49cc,width=2,radius=16")
    + vtg("circle,id=dot,cx=560,cy=250,r=18,stroke=none,fill=#38bdf8")
    + vtg("styledText,id=title,x=340,y=270,style=t,align=center;Drawn over a socket")
    + vtg("styledText,id=code,x=340,y=400,style=c,align=center;telnet · 127.0.0.1 · VTG")
)

PAGE = (
    vtg("textStyle,id=t,font=Georgia,size=36,weight=bold,color=#ffffff")
    + vtg("textStyle,id=b,font=Helvetica Neue,size=18,color=#cbd5e1")
    + vtg("pageBegin,id=remote")
    + vtg("pageOpen,id=card,bg=#082f49f2,w=560,h=260,grow=none")
    + vtg("pageViewport,x=60,y=200,w=560,h=260")
    + vtg("rect,id=frame,x=1,y=1,w=558,h=258,stroke=#38bdf8,fill=none,width=2,radius=14")
    + vtg("styledText,id=title,x=280,y=50,style=t,align=center;A page from far away")
    + vtg("styledText,id=body,x=280,y=130,style=b,align=center;Built off screen on the server, shown in one step.")
    + vtg("pageShow")
)

CLS = vtg("pageEnd") + vtg("clear")

BANNER = (
    b"\r\n\x1b[1mA telnet server that draws\x1b[0m\r\n"
    b"Type \x1b[36mdraw\x1b[0m, \x1b[36mpage\x1b[0m or \x1b[36mcls\x1b[0m. Anything else is echoed back.\r\n"
    b"\x1b]133;A\x07remote $ "
)


def negotiate(sock):
    sock.sendall(bytes([IAC, DO, TTYPE, IAC, DO, NAWS, IAC, WILL, SGA, IAC, WILL, ECHO]))


def strip_iac(data, sock):
    """Answer negotiation, return the data bytes."""
    out = bytearray()
    i = 0
    while i < len(data):
        if data[i] != IAC:
            out.append(data[i])
            i += 1
            continue
        if i + 1 >= len(data):
            break
        command = data[i + 1]
        if command == IAC:
            out.append(IAC)
            i += 2
        elif command in (DO, DONT, WILL, WONT):
            option = data[i + 2] if i + 2 < len(data) else 0
            if command == DO:
                sock.sendall(bytes([IAC, WILL if option in (ECHO, SGA) else WONT, option]))
            elif command == WILL and option == TTYPE:
                sock.sendall(bytes([IAC, SB, TTYPE, 1, IAC, SE]))   # TERMINAL-TYPE SEND
            i += 3
        elif command == SB:
            end = data.find(bytes([IAC, SE]), i)
            block = data[i + 2:end if end != -1 else len(data)]
            if block[:1] == bytes([TTYPE]):
                print("client terminal type:", block[2:].decode(errors="replace"))
            elif block[:1] == bytes([NAWS]) and len(block) >= 5:
                print("client window:", (block[1] << 8) | block[2], "x", (block[3] << 8) | block[4])
            i = (end + 2) if end != -1 else len(data)
        else:
            i += 2
    return bytes(out)


def serve(sock, address):
    print("connected:", address)
    negotiate(sock)
    sock.sendall(BANNER)
    line = bytearray()
    in_escape = False
    holding = False          # a program has the screen: print no prompt
    try:
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            for byte in strip_iac(chunk, sock):
                # A VTG reply answers a question this server asked. It is not
                # something the user typed, so it is never echoed.
                if in_escape:
                    if byte in (0x5c, 0x07):
                        in_escape = False
                    continue
                if byte == 0x1b:
                    in_escape = True
                    continue
                if holding:
                    holding = False
                    sock.sendall(CLS + b"\r\nPage closed.\r\n\x1b]133;A\x07remote $ ")
                    continue
                if byte in (13, 10):
                    sock.sendall(b"\r\n")
                    command = line.decode(errors="replace").strip()
                    line.clear()
                    if command == "draw":
                        sock.sendall(DRAW)
                    elif command == "page":
                        sock.sendall("Showing a page - press any key.\r\n".encode() + PAGE)
                        # Hold the screen: the prompt mark would end the page.
                        holding = True
                        continue
                    elif command == "cls":
                        sock.sendall(CLS)
                    elif command in ("quit", "exit"):
                        sock.sendall(b"bye\r\n")
                        return
                    elif command:
                        sock.sendall(command.encode() + b"\r\n")
                    sock.sendall(b"\x1b]133;A\x07remote $ ")
                elif byte in (8, 127):
                    if line:
                        line.pop()
                        sock.sendall(b"\b \b")
                elif 32 <= byte < 127:
                    line.append(byte)
                    sock.sendall(bytes([byte]))      # The server echoes: it said WILL ECHO.
    finally:
        print("closed:", address)
        sock.close()


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 2323
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", port))
    listener.listen(4)
    print(f"listening on 127.0.0.1:{port} — the iOS simulator can reach this")
    while True:
        sock, address = listener.accept()
        threading.Thread(target=serve, args=(sock, address), daemon=True).start()


if __name__ == "__main__":
    main()
