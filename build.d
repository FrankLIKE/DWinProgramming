module build;

import core.thread : Thread, dur;
import std.algorithm;
import std.array;
import std.exception;
import std.stdio;
import std.string;
import std.path;
import std.file;
import std.process;
import std.parallelism;

string[] RCINCLUDES = [r"C:\Program Files\Microsoft SDKs\Windows\v7.1\Include",
                       r"C:\Program Files\Microsoft Visual Studio 10.0\VC\include",
                       r"C:\Program Files\Microsoft Visual Studio 10.0\VC\atlmfc\include"];
    
extern(C) int kbhit();
extern(C) int getch();    
    
class ForcedExitException : Exception
{
    this()
    {
        super("");
    }    
}

class FailedBuildException : Exception
{
    string[] failedMods;
    string[] errorMsgs;
    this(string[] failedModules, string[] errorMsgs)
    {
        this.failedMods = failedModules;
        this.errorMsgs = errorMsgs;
        super("");
    }    
}
    
bool allExist(string[] paths)
{
    foreach (path; paths)
    {
        if (!path.exists)
            return false;
    }
    return true;
}

void checkWinLib()
{
    win32lib = (compiler == Compiler.DMD)
             ? "dmd_win32.lib"
             : "gdc_win32.lib";
    
    string buildScript = (compiler == Compiler.DMD)
                    ? "dmd_build.bat"
                    : "gdc_build.bat";
    
    enforce(win32lib.exists, "You have to compile the WindowsAPI bindings first. Use the " ~ buildScript ~ " script in the win32 folder");
}

void checkTools()
{
    system("echo int x; > test.h");
    
    auto procInfo = createProcessPipes();
    int res = runProcess("cmd /c htod test.h", procInfo);
    if (res == -1 || res == 1)
    {
        skipHeaderCompile = true;
        //~ writeln("Warning: HTOD missing, won't retranslate .h headers.");
    }
    
    try { std.file.remove("test.h"); } catch {};
    try { std.file.remove("test.d"); } catch {};    
    
    if (compiler == Compiler.DMD)
    {
        system("echo //void > test.rc");
        string cmd = (compiler == Compiler.DMD)
                   ? "cmd /c rc test.rc > nul"
                   : "cmd /c windres test.rc > nul";
        
        auto procInfo2 = createProcessPipes();
        res = runProcess(cmd, procInfo2);
        if (res == -1 || res == 1)
        {
            skipResCompile = true;
            //~ writeln("Warning: RC Compiler not found. Builder will use precompiled resources. See README for more details..");
        }
        
        try { std.file.remove("test.rc");   } catch {};
        try { std.file.remove("test.res");  } catch {};
    }
    
    if (!skipResCompile && !RCINCLUDES.allExist)
    {
        auto includes = getenv("RCINCLUDES").split(";");
        if (includes.allExist && includes.length == RCINCLUDES.length)
        {
            RCINCLUDES = includes;
            skipResCompile = false;
        }
    }   

    if (skipResCompile)
    {
        writeln("Warning: RC Compiler Include dirs not found. Builder will will use precompiled resources.");
    }
    
    writeln();
    Thread.sleep(dur!"seconds"(1));
}

string[] getFilesByExt(string dir, string ext, string ext2 = null)
{
    string[] result;
    foreach (string file; dirEntries(dir, SpanMode.shallow))
    {
        if (file.isFile && (file.getExt.toLower == ext || file.getExt.toLower == ext2))
        {
            result ~= file;
        }
    }
    
    return result;
}

__gshared bool Debug;
__gshared bool cleanOnly;
__gshared bool skipHeaderCompile;
__gshared bool skipResCompile;
__gshared bool silent;
__gshared string win32lib;
enum Compiler { DMD, GDC }
__gshared Compiler compiler = Compiler.DMD;
string soloProject;

alias reduce!("a ~ ' ' ~ b") flatten;

string[] getProjectDirs(string root)
{
    string[] result;
    
    // direntries is not a range in 2.053
    foreach (string dir; dirEntries(root, SpanMode.shallow))
    {
        if (dir.isDir && dir.baseName != "MSDN" && dir.baseName != "Extra2")
        {
            foreach (string subdir; dirEntries(dir, SpanMode.shallow))
            {
                if (subdir.isDir && subdir.baseName != "todo")
                    result ~= subdir;
            }
        }
    }    
    return result;
}

bool buildProject(string dir, out string errorMsg)
{
    string appName = rel2abs(dir).baseName;
    string exeName = rel2abs(dir) ~ r"\" ~ appName ~ ".exe";
    string LIBPATH = r".";
    
    string debugFlags = "-I. -version=Unicode -version=WindowsXP -g -w -wi";
    string releaseFlags = (compiler == Compiler.DMD)
                        ? "-I. -version=Unicode -version=WindowsXP -L-Subsystem:Windows:4"
                        : "-I. -version=Unicode -version=WindowsXP -L--subsystem -Lwindows";
    
    string FLAGS = Debug ? debugFlags : releaseFlags;

    // there's only one resource and header file for each example
    string[] resources;
    string[] headers;
    
    if (!skipResCompile) 
        resources = dir.getFilesByExt("rc");  
    
    if (!skipHeaderCompile) 
        headers = dir.getFilesByExt("h");
    
    // have to clean .o files for GCC
    if (compiler == Compiler.GDC)
    {
        auto procInfo = createProcessPipes();
        int res = runProcess("cmd /c del " ~ rel2abs(dir) ~ r"\*.o > nul", procInfo);
    }
    
    if (resources.length)
    {
        string res_cmd;
        final switch (compiler)
        {
            case Compiler.DMD:
            {
                res_cmd = "cmd /c rc /i" ~ `"` ~ RCINCLUDES[0] ~ `"` ~ 
                          " /i" ~ `"` ~ RCINCLUDES[1] ~ `"` ~
                          " /i" ~ `"` ~ RCINCLUDES[2] ~ `"` ~ 
                          " " ~ resources[0].stripExtension ~ ".rc"
                          " > nul";                
                break;
            }
            
            case Compiler.GDC:
            {
                res_cmd = "windres -i " ~ 
                          resources[0].stripExtension ~ ".rc" ~
                          " -o " ~ 
                          resources[0].stripExtension ~ "_res.o";                
                break;
            }
        }
        
        auto procInfo2 = createProcessPipes();
        int res = runProcess(res_cmd, procInfo2);
        auto output = readProcessPipeString(procInfo2);
        
        if (res == -1 || res == 1)
        {
            errorMsg = format("Compiling resource file failed. Command was:\n%s\n\nError was:\n%s", res_cmd, output);
            return false;
        }
    }

    // @BUG@ htod can't output via -of or -od, causes multithreading issues
    //~ headers.length && system("htod " ~ headers[0]);
    //~ headers.length && system("copy resource.d " ~ rel2abs(dir) ~ r"\resource.d");
    
    // get sources after any .h header files were converted to .d header files
    //~ auto sources   = dir.getFilesByExt("d", "res");
    auto sources   = dir.getFilesByExt("d", (compiler == Compiler.DMD) 
                                             ? "res"
                                             : "o");
    if (sources.length)
    {
        if (!silent) 
            writeln("Building " ~ exeName);
        
        string cmd;
        
        final switch (compiler)
        {
            case Compiler.DMD:
            {
                cmd = "dmd -of" ~ exeName ~
                      " -od" ~ rel2abs(dir) ~ r"\" ~
                      " -I" ~ LIBPATH ~ r"\" ~
                      " " ~ LIBPATH ~ r"\" ~ win32lib ~
                      " " ~ FLAGS ~
                      " " ~ sources.flatten;
              
                break;
            }
            
            case Compiler.GDC:
            {
                cmd = "gdmd.bat -mwindows -of" ~ exeName ~
                      " -od" ~ rel2abs(dir) ~ r"\" ~ 
                      " -Llibwinmm.a -Llibuxtheme.a -Llibcomctl32.a -Llibwinspool.a -Llibws2_32.a -Llibgdi32.a -I" ~ LIBPATH ~ r"\" ~ 
                      " " ~ LIBPATH ~ r"\" ~ win32lib ~
                      " " ~ FLAGS ~ 
                      " " ~ sources.flatten;
                break;
            }
        }
        
        auto procInfo = createProcessPipes();
        int res = runProcess(cmd, procInfo);
        auto output = readProcessPipeString(procInfo);
        
        if (res == -1 || res == 1)
        {
            errorMsg = output;
            return false;
        }
    }
    
    return true;
}

void buildProjectDirs(string[] dirs, bool cleanOnly = false)
{
    __gshared string[] failedBuilds;
    __gshared string[] serialBuilds;
    __gshared string[] errorMsgs;
    
    if (cleanOnly)
        writeln("Cleaning.. ");
    
    //~ foreach (dir; dirs)
    foreach (dir; parallel(dirs, 1))
    {
        if (!cleanOnly && kbhit())
        {
            auto key = cast(dchar)getch();
            stdin.flush();
            enforce(key != 'q', new ForcedExitException);
        }
        
        // @BUG@ Using chdir in parallel builds wreaks havoc on other threads.
        if (dir.baseName == "EdrTest" ||
            dir.baseName == "ShowBit" ||
            dir.baseName == "StrProg")
        {
            serialBuilds ~= dir;
        }
        else
        {
            if (cleanOnly)
            {
                auto procInfo = createProcessPipes();
                runProcess("cmd /c del " ~ dir ~ r"\" ~ "*.obj > nul", procInfo);
                //~ procInfo = createProcessPipes();
                runProcess("cmd /c del " ~ dir ~ r"\" ~ "*.exe > nul", procInfo);
            }
            else
            {
                string errorMsg;
                if (!buildProject(dir, /* out */ errorMsg))
                {
                    errorMsgs ~= errorMsg;
                    failedBuilds ~= rel2abs(dir) ~ r"\" ~ dir.baseName ~ ".exe";
                }
            }
        }
    }
    
    foreach (dir; serialBuilds)
    {
        chdir(rel2abs(dir) ~ r"\");
        
        if (cleanOnly)
        {
            auto procInfo = createProcessPipes();
            runProcess("cmd /c del *.obj > nul", procInfo);
            runProcess("cmd /c del *.o > nul",   procInfo);
            runProcess("cmd /c del *.exe > nul", procInfo);
            runProcess("cmd /c del *.di  > nul", procInfo);
            runProcess("cmd /c del *.dll > nul", procInfo);
            runProcess("cmd /c del *.lib > nul", procInfo);
        }
        else
        {
            string projScript = (compiler == Compiler.DMD)
                              ? "dmd_build.bat"
                              : "gdc_build.bat";
            
            string debugFlags = "-I. -version=Unicode -version=WindowsXP -g -w -wi";
            string releaseFlags = (compiler == Compiler.DMD)
                                ? "-I. -version=Unicode -version=WindowsXP -L-Subsystem:Windows:4"
                                : "-I. -version=Unicode -version=WindowsXP -L--subsystem -Lwindows";
            
            
            auto procInfo3 = createProcessPipes();
            if (projScript.exists)
            {
                int res = runProcess(projScript ~ " " ~ (Debug ? "-g" : "-L-Subsystem:Windows"), procInfo3);
                auto output = readProcessPipeString(procInfo3);
                
                if (res == 1 || res == -1)
                {
                    failedBuilds ~= rel2abs(curdir) ~ r"\.exe";
                    errorMsgs ~= output;
                }
            }
        }
    }
    
    enforce(!failedBuilds.length, new FailedBuildException(failedBuilds, errorMsgs));
}

int main(string[] args)
{
    args.popFront;
    
    foreach (arg; args)
    {
        if (arg.toLower == "clean") cleanOnly = true;
        else if (arg.toLower == "debug") Debug = true;
        else if (arg.toLower == "gdc") compiler = Compiler.GDC;
        else if (arg.toLower == "dmd") compiler = Compiler.DMD;
        else
        {
            if (arg.driveName.length)
            {
                if (arg.exists && arg.isDir)
                {
                    soloProject = arg;
                }
                else
                    enforce(0, "Cannot build project in path: \"" ~ arg ~ 
                              "\". Try wrapping %CD% with quotes when calling build: \"%CD%\"");
            }               
        }
    }
    
    string[] dirs;
    if (soloProject.length)
    {
        silent = true;
        dirs = [rel2abs(soloProject)];
        chdir(r"..\..\..\");
    }
    else
    {
        dirs = getProjectDirs(rel2abs(curdir ~ r"\Samples"));
    }
    
    if (!cleanOnly)
    {
        checkTools();
        checkWinLib();
        
        if (!silent)
        {
            //~ writeln("About to build.");
            
            // @BUG@ The RDMD bundled with DMD 2.053 has input handling bugs,
            // wait for 2.054 to print this out. If you have RDMD from github,
            // you can press 'q' during the build process to force exit.
            
            //~ writeln("About to build. Press 'q' to stop the build process.");
            //~ Thread.sleep(dur!("seconds")(2));
        }
    }    
    
    try
    {
        buildProjectDirs(dirs, cleanOnly);
    }
    catch (ForcedExitException)
    {
        writeln("\nBuild process halted, about to clean..\n");
        Thread.sleep(dur!("seconds")(1));
        cleanOnly = true;
        buildProjectDirs(dirs, cleanOnly);
    }
    catch (FailedBuildException exc)
    {
        writefln("\n%s projects failed to build:", exc.failedMods.length);
        foreach (i, mod; exc.failedMods)
        {
            writeln(mod, "\n", exc.errorMsgs[i]);
        }
        
        return 1;
    }
    
    if (!cleanOnly && !silent)
    {
        writeln("\nAll examples succesfully built.");
    }
    
    return 0;
}

/++ Pipes ++/
import core.memory;
import core.runtime;
import core.thread;
import core.stdc.string;
import std.concurrency;
import std.parallelism;
import std.conv;
import std.exception;
import std.file;
import std.math;
import std.range;
import std.string;
import std.utf;
import std.process;

import win32.windef;
import win32.winuser;
import win32.wingdi;
import win32.winbase;

import std.algorithm;
import std.array;
import std.stdio;
import std.conv;
import std.typetuple;
import std.typecons;
import std.traits;

enum BUFSIZE = 4096;

wstring fromUTF16z(const wchar* s)
{
    if (s is null) return null;

    wchar* ptr;
    for (ptr = cast(wchar*)s; *ptr; ++ptr) {}

    return to!wstring(s[0..ptr-s]);
}

auto toUTF16z(S)(S s)
{
    return toUTFz!(const(wchar)*)(s);
}

struct ProcessInfo
{
    string procName;
    HANDLE childStdinRead;
    HANDLE childStdinWrite;
    HANDLE childStdoutRead;
    HANDLE childStdoutWrite;    
}

ProcessInfo createProcessPipes()
{
    ProcessInfo pi;
    createProcessPipes(pi);
    return pi;
}

void createProcessPipes(ref ProcessInfo procInfo)
{
    SECURITY_ATTRIBUTES saAttr;

    // Set the bInheritHandle flag so pipe handles are inherited.
    saAttr.nLength        = SECURITY_ATTRIBUTES.sizeof;
    saAttr.bInheritHandle = true;

    with (procInfo)
    {
        // Create a pipe for the child process's STDOUT.
        if (!CreatePipe(/* out */ &childStdoutRead, /* out */ &childStdoutWrite, &saAttr, 0) )
            ErrorExit(("StdoutRd CreatePipe"));

        // Ensure the read handle to the pipe for STDOUT is not inherited (sets to 0)
        if (!SetHandleInformation(childStdoutRead, HANDLE_FLAG_INHERIT, 0) )
            ErrorExit(("Stdout SetHandleInformation"));

        // Create a pipe for the child process's STDIN.
        if (!CreatePipe(&childStdinRead, &childStdinWrite, &saAttr, 0))
            ErrorExit(("Stdin CreatePipe"));

        // Ensure the write handle to the pipe for STDIN is not inherited. (sets to 0)
        if (!SetHandleInformation(childStdinWrite, HANDLE_FLAG_INHERIT, 0) )
            ErrorExit(("Stdin SetHandleInformation"));
    }
}

int runProcess(string procName, ProcessInfo procInfo)
{
    // Create a child process that uses the previously created pipes for STDIN and STDOUT.
    auto szCmdline = toUTFz!(wchar*)(procName);

    PROCESS_INFORMATION piProcInfo;
    STARTUPINFO siStartInfo;
    BOOL bSuccess = false;

    // Set up members of the STARTUPINFO structure.
    // This structure specifies the STDIN and STDOUT handles for redirection.
    siStartInfo.cb         = STARTUPINFO.sizeof;
    siStartInfo.hStdError  = procInfo.childStdoutWrite;  // we should replace this
    siStartInfo.hStdOutput = procInfo.childStdoutWrite;
    siStartInfo.hStdInput  = procInfo.childStdinRead;
    siStartInfo.dwFlags |= STARTF_USESTDHANDLES;

    if (CreateProcess(NULL,
                      szCmdline,    // command line
                      NULL,         // process security attributes
                      NULL,         // primary thread security attributes
                      true,         // handles are inherited
                      0,            // creation flags
                      NULL,         // use parent's environment
                      NULL,         // use parent's current directory
                      &siStartInfo, // STARTUPINFO pointer
                      &piProcInfo) == 0) // receives PROCESS_INFORMATION
    {
        ErrorExit("CreateProcess");
    }
    else
    {
        CloseHandle(piProcInfo.hThread);
        WaitForSingleObject(piProcInfo.hProcess, INFINITE);
        DWORD exitCode = 0;

        if (GetExitCodeProcess(piProcInfo.hProcess, &exitCode))
        {
            // successfully retrieved exit code
            return exitCode;
        }

        CloseHandle(piProcInfo.hProcess);
    }
    
    return -1;
}

string readProcessPipeString(ProcessInfo procInfo)
{
    // Read output from the child process's pipe for STDOUT
    // and write to the parent process's pipe for STDOUT.
    // Stop when there is no more data.
    DWORD  dwRead, dwWritten;
    CHAR[BUFSIZE]   chBuf;
    BOOL   bSuccess      = false;
    HANDLE hParentStdOut = GetStdHandle(STD_OUTPUT_HANDLE);
    string buffer;
    
    // Close the write end of the pipe before reading from the
    // read end of the pipe, to control child process execution.
    // The pipe is assumed to have enough buffer space to hold the
    // data the child process has already written to it.
    if (!CloseHandle(procInfo.childStdoutWrite))
        ErrorExit(("StdOutWr CloseHandle"));
    
    while (1)
    {
        bSuccess = ReadFile(procInfo.childStdoutRead, chBuf.ptr, BUFSIZE, &dwRead, NULL);

        if (!bSuccess || dwRead == 0)
            break;

        buffer ~= chBuf[0..dwRead];
    }
    
    return buffer;
}

void ErrorExit(string lpszFunction)
{
    LPVOID lpMsgBuf;
    LPVOID lpDisplayBuf;
    DWORD  dw = GetLastError();

    FormatMessage(
        FORMAT_MESSAGE_ALLOCATE_BUFFER |
        FORMAT_MESSAGE_FROM_SYSTEM |
        FORMAT_MESSAGE_IGNORE_INSERTS,
        NULL,
        dw,
        MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        cast(LPTSTR)&lpMsgBuf,
        0, NULL);    
    
    lpDisplayBuf = cast(LPVOID)LocalAlloc(LMEM_ZEROINIT,
                                      (lstrlen(cast(LPCTSTR)lpMsgBuf) + lstrlen(cast(LPCTSTR)lpszFunction) + 40) * (TCHAR.sizeof));
    
    auto errorMsg = format("%s failed with error %s: %s",
                           lpszFunction,
                           dw,
                           fromUTF16z(cast(wchar*)lpMsgBuf)
                           );
                          
    throw new ProcessExecutionException(errorMsg, __FILE__, __LINE__);
}


import std.exception;

class BuildException : Exception
{
    string errorMsg;
    this(string msg) 
    {
        errorMsg = msg;
        super(msg);
    }
    
    this(string msg, string file, size_t line, Exception next = null)
    {
        errorMsg = msg;
        super(msg, file, line, next);
    }    
}

string ExceptionImpl(string name)
{
    return(`
    class ` ~ name ~ ` : BuildException
    {
        this(string msg) 
        {
            super(msg);
        }
        
        this(string msg, string file, size_t line, Exception next = null)
        {
            super(msg, file, line, next);
        }
    }`);     
}

mixin(ExceptionImpl("CompilerError"));
mixin(ExceptionImpl("ModuleException"));
mixin(ExceptionImpl("ParseException"));
mixin(ExceptionImpl("ProcessExecutionException"));
