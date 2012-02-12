/+
 + (c) Reliable Software, 1997, 98
 + Ported to the D Programming Language by Andrej Mitrovic, 2011.
 +/

module view;

import canvas;
import model;

struct View
{
    void SetSize(int cxNew, int cyNew)
    {
        _cx = cxNew;
        _cy = cyNew;
    }

    void Paint(Canvas canvas, Model model)
    {
        canvas.Text(12, 1, model.GetText());
        canvas.Line(10, 0, 10, _cy);
    }

protected:

    int _cx;
    int _cy;
}
