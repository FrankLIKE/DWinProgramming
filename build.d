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

import pipes;

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
    
    auto res = execute("cmd /c htod test.h").status;
    if (res == -1 || res == 1)
    {
        skipHeaderCompile = true;
        writeln("Warning: HTOD missing, won't retranslate .h headers.");
    }
    
    try { std.file.remove("test.h"); } catch {};
    try { std.file.remove("test.d"); } catch {};    
    
    if (compiler == Compiler.DMD)
    {
        system("echo //void > test.rc");
        string cmd = (compiler == Compiler.DMD)
                   ? "cmd /c rc test.rc > nul"
                   : "cmd /c windres test.rc > nul";
        
        res = execute(cmd).status;
        if (res == -1 || res == 1)
        {
            skipResCompile = true;
            writeln("Warning: RC Compiler not found. Builder will use precompiled resources. See README for more details..");
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
        else
            writeln("Won't compile resources.");
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
        execute("cmd /c del " ~ rel2abs(dir) ~ r"\*.o > nul");
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
                          " " ~ resources[0].stripExtension ~ ".rc";                
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
        
        auto pc = execute(res_cmd);
        auto output = pc.output;
        auto res = pc.status;
        
        if (res == -1 || res == 1)
        {
            errorMsg = format("Compiling resource file failed. Command was:\n%s\n\nError was:\n%s", res_cmd, output);
            return false;
        }
    }

    // @BUG@ htod can't output via -of or -od, causes multithreading issues.
    // We're distributing precompiled .d files now.
    //~ headers.length && system("htod " ~ headers[0] ~ " " ~ r"-IC:\dm\include");
    //~ headers.length && system("copy resource.d " ~ rel2abs(dir) ~ r"\resource.d > nul");
    
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
        
        auto pc = execute(cmd);
        auto output = pc.output;
        auto res = pc.status;
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
                execute("cmd /c del " ~ dir ~ r"\" ~ "*.obj > nul");
                execute("cmd /c del " ~ dir ~ r"\" ~ "*.exe > nul");
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
            execute("cmd /c del *.obj > nul");
            execute("cmd /c del *.o > nul");
            execute("cmd /c del *.exe > nul");
            execute("cmd /c del *.di  > nul");
            execute("cmd /c del *.dll > nul");
            execute("cmd /c del *.lib > nul");
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
                auto pc = execute(projScript ~ " " ~ (Debug ? "-g" : "-L-Subsystem:Windows"));
                auto output = pc.output;
                auto res = pc.status;
                
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
        if (soloProject.length)
        {
            writefln("%s failed to build.\n%s", exc.failedMods[0], exc.errorMsgs[0]);
        }
        else
        {
            writefln("%s projects failed to build:", exc.failedMods.length);
            foreach (i, mod; exc.failedMods)
            {
                writeln(mod, "\n", exc.errorMsgs[i]);
            }
        }
            
        return 1;
    }
    
    if (!cleanOnly && !silent)
    {
        writeln("\nAll examples succesfully built.");
    }
    
    return 0;
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
