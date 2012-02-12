/+
 + (c) Reliable Software, 1997, 98
 + Ported to the D Programming Language by Andrej Mitrovic, 2011.
 +/

module model;

import std.utf;

struct Model
{
public:
    this(string str)
    {
        SetText(str);
    }

    void SetText(string str)
    {
        _text = str;
    }

    string GetText()
    {
        return _text;
    }

    size_t GetLen()
    {
        return _text.count;
    }

private:
    string _text;
}
