/+
 + (c) Reliable Software, 1997, 98
 + Ported to the D Programming Language by Andrej Mitrovic, 2011.
 +/

module winmaker;

pragma(lib, "gdi32.lib");
pragma(lib, "winmm.lib");

import win32.mmsystem;
import win32.windef;
import win32.winuser;
import win32.wingdi;

import core.stdc.config;
import std.algorithm;
import std.exception;
import std.utf;
import std.conv;

import winex;
//~ import utfhelp;

auto T WinGetLong(T)(HWND hwnd, int which = GWL_USERDATA)
{
    return cast(T)GetWindowLong(hwnd, which);
}

void WinSetLong(T)(HWND hwnd, T value, int which = GWL_USERDATA)
{
    SetWindowLong(hwnd, which, cast(c_long)(value));
}

struct ResString
{
    enum MAX_RESSTRING = 255;

    // String Resource
    this(HINSTANCE hInst, int resId)
    {
        enforce(LoadString(hInst, resId, _buf.ptr, MAX_RESSTRING + 1),
                new WinException("Load String failed"));
    }

    string toString()
    {
        return to!string(cast(wstring)_buf[0 .. _buf[].countUntil('\0')]);
    }

private:
    wchar _buf[MAX_RESSTRING + 1] = 0;
}


// Use for built-in classes
class WinSimpleClass
{
public:
    this(string name, HINSTANCE hInst)
    {
        _name      = name;
        _hInstance = hInst;
    }

    this(int resId, HINSTANCE hInst)
    {
        _hInstance = hInst;
        _name      = ResString(hInst, resId).toString;
    }

    auto GetName()
    {
        return _name.toUTF16z;
    }

    HINSTANCE GetInstance()
    {
        return _hInstance;
    }

    HWND GetRunningWindow()
    {
        HWND hwnd = FindWindow(GetName(), null);

        if (IsWindow(hwnd))
        {
            HWND hwndPopup = GetLastActivePopup(hwnd);

            if (IsWindow(hwndPopup))
                hwnd = hwndPopup;
        }
        else
            hwnd = null;

        return hwnd;
    }

protected:
    HINSTANCE _hInstance;
    string _name;
}

class WinClass : WinSimpleClass
{
public:
    this(int resId, HINSTANCE hInst, WNDPROC wndProc)
    {
        super(resId, hInst);
        _class.lpfnWndProc = wndProc;
        SetDefaults();
    }

    this(string className, HINSTANCE hInst, WNDPROC wndProc)
    {
        super(className, hInst);
        _class.lpfnWndProc = wndProc;
        SetDefaults();
    }

    void SetBgSysColor(int sysColor)
    {
        _class.hbrBackground = cast(HBRUSH)(sysColor + 1);
    }

    void SetResIcons(ushort resId)
    {
        _class.hIcon = cast(HICON)(
            LoadImage(
                _class.hInstance,
                MAKEINTRESOURCE(resId),
                IMAGE_ICON,
                GetSystemMetrics(SM_CXICON),
                GetSystemMetrics(SM_CYICON),
                0));

        // Small icon can be loaded from the same resource
        _class.hIconSm = cast(HICON)(
            LoadImage(
                _class.hInstance,
                MAKEINTRESOURCE(resId),
                IMAGE_ICON,
                GetSystemMetrics(SM_CXSMICON),
                GetSystemMetrics(SM_CYSMICON),
                0));
    }

    void Register()
    {
        enforce(RegisterClassEx(&_class) != 0, new WinException("Internal error: RegisterClassEx failed."));
    }

protected:
    void SetDefaults()
    {
        // Provide reasonable default values
        _class.cbSize        = WNDCLASSEX.sizeof;
        _class.style         = 0;
        _class.lpszClassName = GetName();
        _class.hInstance     = GetInstance();
        _class.hIcon         = null;
        _class.hIconSm       = null;
        _class.lpszMenuName  = null;
        _class.cbClsExtra    = 0;
        _class.cbWndExtra    = 0;
        _class.hbrBackground = cast(HBRUSH)(COLOR_WINDOW + 1);
        _class.hCursor       = LoadCursor(null, IDC_ARROW);
    }

    WNDCLASSEX _class;
}

class TopWinClass : WinClass
{
    // Makes top window class with icons and menu
    this(ushort resId, HINSTANCE hInst, WNDPROC wndProc)
    {
        super(resId, hInst, wndProc);
        SetResIcons(resId);
        _class.lpszMenuName = MAKEINTRESOURCE(resId);
    }
}

class WinMaker
{
    //~ public:

    // The maker of a window of a given class
    this(WinClass winClass)
    {
        _hwnd       = null;
        _class      = winClass;
        _exStyle    = 0;             // extended window style
        _windowName = null;          // pointer to window name
        _style      = WS_OVERLAPPED; // window style
        _x          = CW_USEDEFAULT; // horizontal position of window
        _y          = 0;             // vertical position of window
        _width      = CW_USEDEFAULT; // window width
        _height     = 0;             // window height
        _hWndParent = null;          // handle to parent or owner window
        _hMenu      = null;          // handle to menu, or child-window identifier
        _data       = null;          // pointer to window-creation data
    }

    void AddCaption(string caption)
    {
        _windowName = caption;
    }

    void AddSysMenu()
    {
        _style |= WS_SYSMENU;
    }

    void AddVScrollBar()
    {
        _style |= WS_VSCROLL;
    }

    void AddHScrollBar()
    {
        _style |= WS_HSCROLL;
    }

    void Create()
    {
        _hwnd = CreateWindowEx(
            _exStyle,
            _class.GetName(),
            _windowName.toUTF16z,
            _style,
            _x,
            _y,
            _width,
            _height,
            _hWndParent,
            _hMenu,
            _class.GetInstance(),
            _data);

        enforce(_hwnd !is null, new WinException("Internal error: Window Creation Failed."));
    }

    void Show(int nCmdShow = SW_SHOWNORMAL)
    {
        ShowWindow(_hwnd, nCmdShow);
        UpdateWindow(_hwnd);
    }

protected:
    WinClass _class;
    HWND _hwnd;

    DWORD  _exStyle;        // extended window style
    string _windowName;     // pointer to window name
    DWORD  _style;          // window style
    int   _x;               // horizontal position of window
    int   _y;               // vertical position of window
    int   _width;           // window width
    int   _height;          // window height
    HWND  _hWndParent;      // handle to parent or owner window
    HMENU _hMenu;           // handle to menu, or child-window identifier
    void* _data;            // pointer to window-creation data
}

class TopWinMaker : WinMaker
{
    // Makes top overlapped window with caption
    this(WinClass winClass, string caption)
    {
        super(winClass);
        _style      = WS_OVERLAPPEDWINDOW | WS_VISIBLE;
        _windowName = caption;
    }
}
