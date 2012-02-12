/+
 + (c) Reliable Software, 1997, 98
 + Ported to the D Programming Language by Andrej Mitrovic, 2011.
 +/

module control;

import view;
import model;
import canvas;
import winmaker;
import winex;

import resource;

pragma(lib, "gdi32.lib");
pragma(lib, "winmm.lib");

import win32.mmsystem;
import win32.windef;
import win32.winuser;
import win32.wingdi;

import std.utf;
import core.stdc.config;

class Controller
{
public:
    this(HWND hwnd, CREATESTRUCT * pCreate)
    {
        _hwnd  = hwnd;
        _model = Model("Generic");
    }

    void Size(int cx, int cy)
    {
        _view.SetSize(cx, cy);
    }

    void Paint()
    {
        auto canvas = new PaintCanvas(_hwnd);
        _view.Paint(canvas, _model);
    }

    // Menu commands processing
    void Command(int cmd)
    {
        switch (cmd)
        {
            case IDM_EXIT:
                SendMessage(_hwnd, WM_CLOSE, 0, 0L);
                break;

            case IDM_HELP:
                MessageBox(_hwnd, "Go figure!",
                           "Generic", MB_ICONINFORMATION | MB_OK);
                break;

            case IDM_ABOUT:
            {
                // Instance handle is available through HWND
                HINSTANCE hInst = WinGetLong!(HINSTANCE)(_hwnd, GWL_HINSTANCE);
                DialogBox(hInst,
                          MAKEINTRESOURCE(IDD_ABOUT),
                          _hwnd,
                          &AboutDlgProc);
                break;
            }

            default:
        }
    }

    ~this()  // unreliable
    {
        PostQuitMessage(0);
    }

private:

    HWND _hwnd;

    Model _model;
    View  _view;
}

struct ClassWrap
{
    Controller ctrl;
}


alias ClassWrap* PClassWrap;

// Window Procedure
extern (Windows)
LRESULT MainWndProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam)
{
    auto pClassWrap = WinGetLong!(PClassWrap)(hwnd);

    switch (message)
    {
        case WM_CREATE:
        {
            try
            {
                static ClassWrap wrap;
                wrap.ctrl = new Controller(hwnd, cast(CREATESTRUCT*)lParam);
                WinSetLong!(PClassWrap)(hwnd, &wrap);
            }
            catch (WinException e)
            {
                MessageBox(hwnd, toUTF16z(e.msg), "Initialization",
                           MB_ICONEXCLAMATION | MB_OK);
                return -1;
            }
            catch (Exception e)
            {
                MessageBox(hwnd, "Unknown Error", "Initialization",
                           MB_ICONEXCLAMATION | MB_OK);
                return -1;
            }
            return 0;
        }

        case WM_SIZE:
            pClassWrap.ctrl.Size(LOWORD(lParam), HIWORD(lParam));
            return 0;

        case WM_PAINT:
            pClassWrap.ctrl.Paint();
            return 0;

        case WM_COMMAND:
            pClassWrap.ctrl.Command(LOWORD(wParam));
            return 0;

        case WM_DESTROY:
            WinSetLong!(PClassWrap)(hwnd, null);
            clear(pClassWrap.ctrl);
            return 0;

        default:
    }

    return DefWindowProc(hwnd, message, wParam, lParam);
}

// "About" dialog box procedure
// Process messages from dialog box
// Caution: use Windows BOOL, not C++ bool
extern (Windows)
BOOL AboutDlgProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam)
{
    switch (message)
    {
        case WM_INITDIALOG:
            return TRUE;

        case WM_COMMAND:
        {
            switch (LOWORD(wParam))
            {
                case IDOK:
                case IDCANCEL:
                    EndDialog(hwnd, 0);
                    return TRUE;

                default:
            }

            break;
        }

        default:
    }

    return FALSE;
}
