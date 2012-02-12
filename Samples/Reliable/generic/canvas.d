/+
 + (c) Reliable Software, 1997, 98
 + Ported to the D Programming Language by Andrej Mitrovic, 2011.
 +/

module canvas;

pragma(lib, "gdi32.lib");
pragma(lib, "winmm.lib");

import std.conv;
import std.utf;

import win32.mmsystem;
import win32.windef;
import win32.winuser;
import win32.wingdi;

// Encapsulate Windows Device Context
abstract class Canvas
{
    void Line(int x1, int y1, int x2, int y2)
    {
        MoveToEx(_hdc, x1, y1, null);
        LineTo(_hdc, x2, y2);
    }

    void Text(int x, int y, string buf)
    {
        TextOut(_hdc, x, y, buf.toUTF16z, buf.count);
    }

    void Char(int x, int y, char c)
    {
        TextOut(_hdc, x, y, toUTF16z(to!string(c)), 1);
    }

    /* Keep adding new methods as needed */

protected:

    this(HDC hdc)
    {
        _hdc = hdc;
    }

    HDC _hdc;
}

// Use for painting in response to WM_PAINT
class PaintCanvas : Canvas
{
public:
    this(HWND hwnd)
    {
        super(BeginPaint(hwnd, &_paint));
        _hwnd = hwnd;
    }

    ~this()  // todo: unreliable
    {
        EndPaint(_hwnd, &_paint);
    }

protected:

    PAINTSTRUCT _paint;
    HWND _hwnd;
}
