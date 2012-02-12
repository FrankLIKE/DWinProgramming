/+
 + (c) Reliable Software, 1997, 98
 + Ported to the D Programming Language by Andrej Mitrovic, 2011.
 +/

module generic;

import core.runtime;
import std.string;
import std.utf;

pragma(lib, "gdi32.lib");
pragma(lib, "winmm.lib");

import win32.mmsystem;
import win32.windef;
import win32.winuser;
import win32.wingdi;

import canvas;
import control;
import model;
import winex;
import view;
import winmaker;

import resource;

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
    try
    {
        // Create top window class
        TopWinClass topWinClass = new TopWinClass(ID_MAIN, hInstance, &MainWndProc);

        // Is there a running instance of this program?
        HWND hwndOther = topWinClass.GetRunningWindow();

        if (hwndOther != null)
        {
            SetForegroundWindow(hwndOther);

            if (IsIconic(hwndOther))  // if minimized, restore
                ShowWindow(hwndOther, SW_RESTORE);

            return 0;
        }

        topWinClass.Register();

        // Create top window
        auto caption = ResString(hInstance, ID_CAPTION);
        auto topWin  = new TopWinMaker(topWinClass, caption.toString);
        topWin.Create();
        topWin.Show(iCmdShow);

        // The main message loop
        MSG msg;
        int status = GetMessage(&msg, null, 0, 0);

        while (status != 0)
        {
            if (status == -1)
                return -1;

            TranslateMessage(&msg);
            DispatchMessage(&msg);
            status = GetMessage(&msg, null, 0, 0);
        }

        return msg.wParam;
    }
    catch (WinException e)
    {
        string buf = format("%s, Error %s", e.GetMessage(), e.GetError());
        MessageBox(null, buf.toUTF16z, "Exception", MB_ICONEXCLAMATION | MB_OK);
    }
    catch (Exception e)
    {
        MessageBox(null, "Unknown", "Exception", MB_ICONEXCLAMATION | MB_OK);
    }

    return 0;
}
