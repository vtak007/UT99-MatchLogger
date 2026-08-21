//=============================================================================
// MLFileWriter.uc
// Rev 6
// File writing utility for MatchLogger
// Rev 6: restores the Rev 4 temp-file design. StatLogFile MUST DIFFER from
//        StatLogFinal. On CloseLog() the engine finalizes by moving
//        StatLogFile -> StatLogFinal; that move deletes the destination first,
//        so if the two names are identical it deletes the source and the move
//        fails ("Error moving file 'X' to 'X' - cannot find the file").
//        Writing to <name>.tmp and finalizing to <name> avoids that.
// Uses StatLogFile as base for file I/O capabilities
//=============================================================================
class MLFileWriter extends StatLogFile;

var private bool   bFileOpen;
var private string CurrentFileName;
var private string FinalFileName;
var private string TempFileName;

// Open a file for writing
function bool OpenFile(string FileName)
{
    if (FileName == "")
    {
        Log("MatchLogger: ERROR - OpenFile called with an empty filename");
        return False;
    }

    // Write to <name>.tmp, finalize to <name> on CloseLog(). The two MUST differ
    // (see header): identical names make the finalize move delete its own source.
    FinalFileName   = FileName;
    TempFileName    = FileName $ ".tmp";
    CurrentFileName = FinalFileName;

    // Hard guard against the Rev 5 regression: never let the working file and the
    // finalize target resolve to the same path.
    if (TempFileName == FinalFileName)
    {
        Log("MatchLogger: ERROR - temp and final names identical ('" $ FinalFileName $ "'); aborting to avoid move-to-self failure");
        return False;
    }

    StatLogFile  = TempFileName;
    StatLogFinal = FinalFileName;

    OpenLog();
    bFileOpen = True;

    return True;
}

// Write a line to the file
function WriteLine(string Text)
{
    if (bFileOpen)
        FileLog(Text);
}

// Write text without newline.
// StatLogFile does not provide true raw streaming here,
// so this behaves the same as WriteLine.
function WriteText(string Text)
{
    if (bFileOpen)
        FileLog(Text);
}

// Close the file
function CloseFile()
{
    if (bFileOpen)
    {
        FileFlush();
        CloseLog();
        bFileOpen = False;
    }
}

// Destructor - ensure file is closed
function Destroyed()
{
    CloseFile();
    Super.Destroyed();
}

defaultproperties
{
    bFileOpen=False
    bWorld=False
}