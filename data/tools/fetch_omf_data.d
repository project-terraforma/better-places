#!/usr/bin/env rdmd
import std;

enum Target { santa_cruz, sc=santa_cruz }
enum Theme { place, building, building_part, address }
enum DataFormat { geojson, geoparquet }
enum Action { fetch, refetch, clean }

string BOUNDING_BOX (Target target) {
    final switch (target) {
        case Target.santa_cruz: return "-122.081623,36.946668,-121.932878,37.003170";
    }
    assert(0);
}

void main (string[] args) {
    args
        .parseArgs()
        .run()
        .wrapErrors();
}
void die (string msg, int errc = -1) {
    import core.stdc.stdlib: exit;
    writeln(msg);
    exit(errc);
}
T wrapErrors (T)(lazy T expr) {
    try {
        return expr;
    } catch (Throwable e) {
        die("%s".format(e), -1);
    }
}
struct Args {
    Action action = Action.fetch;
    DataFormat format;
    Target[] targets;
    Theme[] themes;
    bool parallel = false;
    bool all = false;
}
bool parse (E)(string input, out E result) if (is(E == enum)) {
    static foreach (m; __traits(allMembers, E)) {
        if (m == input) { result = mixin(E.stringof~"."~m); return true; }
    }
    return false;
}
T parse(T)(string input) if (is(T == enum)) {
    T result;
    enforce(input.parse(result), "invalid %s '%s' (expected %s)".format(
        T.stringof, input, enumerateMembers!T.join(" | ")
    ));
    return result;
}
string[] enumerateMembers (E)() if (is(E == enum)) {
    string[] values;
    static foreach (m; __traits(allMembers, E)) {
        values ~= m;
    }
    return values;
}
E[] allValues (E)() if (is(E == enum)) {
    E[] values;
    static foreach (m; __traits(allMembers, E)) {
        values ~= mixin("E."~m);
    }
    return values.sort.uniq.array;
}

Args parseArgs (string[] args) {
    Args r;
    {
        string target = null;
        string theme = null;
        string dataFormat = null;
        bool doRefetch = false;
        bool doClean = false;

        auto hi = args.getopt(
            std.getopt.config.caseSensitive,
            "at", &target,
            "t|themes", &theme,
            "f|format", &dataFormat,
            "p|parallel", &r.parallel,
            "r|refetch", &doRefetch,
            "clean", &doClean,
            "all", &r.all
        );
        if (hi.helpWanted) {
            defaultGetoptPrinter(args[0], hi.options);
        }
        if (target !is null) {
            r.targets ~= target.parse!Target;
        }
        if (theme !is null) {
            r.themes ~= theme.parse!Theme;
        }
        if (dataFormat !is null) {
            r.format = dataFormat.parse!DataFormat;
        }
        if (doRefetch) {
            r.action = Action.refetch;
        }
        if (doClean) {
            r.action = Action.clean;
        }
    }

    string[] invalidArgs;
    foreach (arg; args[1..$]) {
        Target target;
        Theme theme;
        if (arg == "all") r.all = true;
        else if (arg.parse(target)) r.targets ~= target;
        else if (arg.parse(theme)) r.themes ~= theme;
        else invalidArgs ~= arg;
    }
    enforce(!invalidArgs.length, "invalid argument(s): %s\n\texpected %s".format(
        invalidArgs.join(", "),
        (["all"]
            ~ enumerateMembers!Target
            ~ enumerateMembers!Theme
        ).join(" | "))
    );

    return r;
}

struct FetchRequest {
    Target target;
    Theme theme;
    DataFormat format;
    Action action;
}
FetchRequest[] requests (Args a) {
    auto targets = a.targets.length ? a.targets : allValues!Target;
    auto themes = a.themes.length ? a.themes : allValues!Theme;
    FetchRequest[] r;
    foreach (target; targets) {
        foreach (theme; themes) {
            r ~= FetchRequest(target, theme, a.format, a.action);
        }
    }
    return r;
}

void run (Args a) {
    writefln("fetching %s, %s with format %s", a.themes, a.targets, a.format);

    // write out bounds files if they don't exist
    foreach (target; (a.targets.length ? a.targets : allValues!Target)) {
        string targetDirectory = buildPath("data", "omf", target.to!string);
        string targetBoundsFile = buildPath(targetDirectory, ".bounds.txt");

        if (a.action == Action.clean) {
            if (targetBoundsFile.exists) {
                std.file.remove(targetBoundsFile);
            }
            continue;
        }
        if (!targetBoundsFile.exists) {
            if (!targetDirectory.exists) {
                targetDirectory.mkdirRecurse;
            }
            std.file.write(targetBoundsFile, BOUNDING_BOX(target));
        }
    }

    // run fetch / clean etc requests
    if (a.parallel) {
        foreach (req; a.requests.parallel) {
            req.run();
        }
    } else {
        foreach (req; a.requests) {
            req.run();
        }
    }
}
void run (FetchRequest req) {
    writefln("running %s", req);
    string targetDirectory = buildPath("data", "omf", req.target.to!string);

    string dataPath = buildPath(targetDirectory,
        "%s.%s".format(req.theme.to!string, req.format.to!string));

    if (req.action == Action.clean) {
        if (dataPath.exists) {
            writefln("\033[0;1mRemoving: %s\033[0m", dataPath);
            std.file.remove(dataPath);
        }
        return;
    }
    if (dataPath.exists && !req.action == Action.refetch) {
        writefln("\033[0;1mskipping: %s\033[0m", dataPath);
        return;
    }
    if (!targetDirectory.exists) {
        targetDirectory.mkdirRecurse();
    }
    string[] runArgs = ["overturemaps", "download"];
    runArgs ~= "-o"; runArgs ~= dataPath;
    runArgs ~= "-f"; runArgs ~= req.format.to!string;
    runArgs ~= "-t"; runArgs ~= req.theme.to!string;
    runArgs ~= "--bbox"; runArgs ~= req.target.BOUNDING_BOX;
    writefln("\033[0;1mRunning `%s`\033[0m", runArgs);
    int res = runArgs.join(" ").spawnShell().wait();
    if (res != 0) {
        stderr.write("\033[0;1;31mFAILED: %s\033[0m".format(runArgs));
        enforce(false, "FAILED: %s".format(runArgs));
    }
}
