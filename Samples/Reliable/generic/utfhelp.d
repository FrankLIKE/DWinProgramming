module utfhelp;

// See Issue 6157

import std.conv;
import std.traits;
import core.stdc.string;
import core.stdc.wchar_;

/// ditto
T toImpl(T, S) (S s)

if (isPointer!S && is (S : const(char)*) &&
    isSomeString!T)
{
    return s ? cast(T)s[0 .. strlen(s)].dup : cast(T)null;
}

/// ditto
T toImpl(T, S) (S s)

if (isPointer!S && is (S : const(wchar)*) &&
    isSomeString!T)
{
    return s ? to!T(s[0 .. wcslen(s)]) : cast(T)null;
}

/// ditto
T toImpl(T, S) (S s)

if (isPointer!S && is (S : const(dchar)*) &&
    isSomeString!T)
{
    if (s is null)
        return cast(T)null;

    dchar* ptr;

    for (ptr = cast(dchar*)s; *ptr; ++ptr)
    {
    }

    return to!T(s[0..ptr - s]);
}

/// Converts const/non-const char[]/wchar[]/dchar[] to char*/wchar*/dchar* by
/// forwarding to std.utf.toUTFz.
T toImpl(T, S) (S s)

if (isPointer!T &&
    is (T : const(char)*) || is (T : const(wchar)*) || is (T : const(dchar)*) &&
    isSomeString!S)
{
    import std.utf;
    return toUTFz!T(s);
}

alias toImpl to;

unittest
{
    alias toImpl to;

    string  utf_8_src  = "ùûöàßÆÀć";
    wstring utf_16_src = "ùûöàßÆÀć"w;
    dstring utf_32_src = "ùûöàßÆÀć"d;

    /* non-const tests */
    char * utf_8_ptr;
    wchar* utf_16_ptr;
    dchar* utf_32_ptr;

    utf_8_ptr = to!(char*)(utf_8_src);
    assert(to!string(utf_8_ptr) == utf_8_src);

    utf_8_ptr = to!(char*)(utf_16_src);
    assert(to!string(utf_8_ptr) == utf_8_src);

    utf_8_ptr = to!(char*)(utf_32_src);
    assert(to!string(utf_8_ptr) == utf_8_src);

    utf_16_ptr = to!(wchar*)(utf_8_src);
    assert(to!wstring(utf_16_ptr) == utf_16_src);

    utf_16_ptr = to!(wchar*)(utf_16_src);
    assert(to!wstring(utf_16_ptr) == utf_16_src);

    utf_16_ptr = to!(wchar*)(utf_32_src);
    assert(to!wstring(utf_16_ptr) == utf_16_src);

    utf_32_ptr = to!(dchar*)(utf_8_src);
    assert(to!dstring(utf_16_ptr) == utf_32_src);

    utf_32_ptr = to!(dchar*)(utf_16_src);
    assert(to!dstring(utf_16_ptr) == utf_32_src);

    utf_32_ptr = to!(dchar*)(utf_32_src);
    assert(to!dstring(utf_16_ptr) == utf_32_src);

    /* const tests */
    auto c_utf8_temp1 = to!(const(char*))(utf_8_src);
    assert(to!string(c_utf8_temp1) == utf_8_src);

    auto c_utf8_temp2 = to!(const(char*))(utf_16_src);
    assert(to!string(c_utf8_temp2) == utf_8_src);

    auto c_utf8_temp3 = to!(const(char*))(utf_32_src);
    assert(to!string(c_utf8_temp3) == utf_8_src);

    auto c_utf16_temp1 = to!(const(wchar*))(utf_8_src);
    assert(to!wstring(c_utf16_temp1) == utf_16_src);

    auto c_utf16_temp2 = to!(const(wchar*))(utf_16_src);
    assert(to!wstring(c_utf16_temp2) == utf_16_src);

    auto c_utf16_temp3 = to!(const(wchar*))(utf_32_src);
    assert(to!wstring(c_utf16_temp3) == utf_16_src);

    auto c_utf32_temp1 = to!(const(dchar*))(utf_8_src);
    assert(to!dstring(c_utf32_temp1) == utf_32_src);

    auto c_utf32_temp2 = to!(const(dchar*))(utf_16_src);
    assert(to!dstring(c_utf32_temp2) == utf_32_src);

    auto c_utf32_temp3 = to!(const(dchar*))(utf_32_src);
    assert(to!dstring(c_utf32_temp3) == utf_32_src);
}
