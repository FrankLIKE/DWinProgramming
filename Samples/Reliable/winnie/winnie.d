/+
 + (c) Bartosz Milewski, 1995, 97
 + Ported to the D Programming Language by Andrej Mitrovic, 2011.
 +/

module winnie;

import core.runtime;
import std.string;
import std.utf;

pragma(lib, "gdi32.lib");
pragma(lib, "winmm.lib");

import win32.mmsystem;
import win32.windef;
import win32.winuser;
import win32.wingdi;

extern (Windows)
int WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int iCmdShow)
{
    int result;
    void exceptionHandler(Throwable e)
    {
        throw e;
    }

    try
    {
        Runtime.initialize(&exceptionHandler);
        result = myWinMain(hInstance, hPrevInstance, lpCmdLine, iCmdShow);
        Runtime.terminate(&exceptionHandler);
    }
    catch (Throwable o)
    {
        MessageBox(null, o.toString().toUTF16z, "Error", MB_OK | MB_ICONEXCLAMATION);
        result = 0;
    }

    return result;
}

int myWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int iCmdShow)
{
    string className = "Winnie";
    MSG msg;

    // Define a Window Class and register it under the name "Winnie"
    auto winClass = new WinClass(&WindowProcedure, className, hInstance);
    winClass.Register();

    // Create and show a window
    auto win = new WinMaker("Hello Windows!", className, hInstance);
    win.Show(iCmdShow);

    while (GetMessage(&msg, NULL, 0, 0))
    {
        DispatchMessage(&msg);
    }

    return msg.wParam;
}

// We'll be creating windows of this Class in our program
class WinClass
{
public:
    this(WNDPROC wndProc, string className, HINSTANCE hInst)
    {
        _class.style         = 0;
        _class.lpfnWndProc   = wndProc; // Window Procedure: mandatory
        _class.cbClsExtra    = 0;
        _class.cbWndExtra    = 0;
        _class.hInstance     = hInst;                          // owner of the class: mandatory
        _class.hIcon         = null;
        _class.hCursor       = LoadCursor(null, IDC_ARROW);       // optional
        _class.hbrBackground = cast(HBRUSH)(COLOR_WINDOW + 1); // optional
        _class.lpszMenuName  = null;
        _class.lpszClassName = className.toUTF16z;             // mandatory
    }

    void Register()
    {
        RegisterClass(&_class);
    }

private:
    WNDCLASS _class;
}

// Creates a window of a given Class
class WinMaker
{
    this()
    {
        _hwnd = null;
    }

    this(string caption, string className, HINSTANCE hInstance)
    {
        _hwnd = CreateWindow(
            className.toUTF16z,           // name of a registered window class
            caption.toUTF16z,             // window caption
            WS_OVERLAPPEDWINDOW, // window style
            CW_USEDEFAULT,       // x position
            CW_USEDEFAULT,       // y position
            CW_USEDEFAULT,       // witdh
            CW_USEDEFAULT,       // height
            null,                   // handle to parent window
            null,                   // handle to menu
            hInstance,           // application instance
            null);                  // window creation data
    }

    void Show(int cmdShow)
    {
        ShowWindow(_hwnd, cmdShow);
        UpdateWindow(_hwnd);
    }

protected:
    HWND _hwnd;
}

// Window Procedure called by Windows with all kinds of messages

extern(Windows)
LRESULT WindowProcedure(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam)
{
    switch (message)
    {
        // In this simple program, this is the only message we are processing
        case WM_DESTROY:
            PostQuitMessage(0);
            return 0; // return zero when processed

        default:
    }

    // All the unprocessed messages go there, to be dealt in some default way
    return DefWindowProc(hwnd, message, wParam, lParam);
}
