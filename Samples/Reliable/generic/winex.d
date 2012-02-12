/+
 + (c) Reliable Software, 1997, 98
 + Ported to the D Programming Language by Andrej Mitrovic, 2011.
 +/

module winex;

pragma(lib, "gdi32.lib");
pragma(lib, "winmm.lib");

import win32.winbase;
import win32.mmsystem;
import win32.windef;
import win32.winuser;
import win32.wingdi;

class WinException : Exception
{
public:
    this(string msg)
    {
        super(msg);
        _err = GetLastError();
    }

    DWORD GetError() const
    {
        return _err;
    }

    // todo: implement
    string GetMessage() const
    {
        return "";
    }

private:
    DWORD _err;
}
