<#
=====================================================================
  斬る  Santoku Knives V14 (Fileslicer)  (ファイル・スライサー)
  --------------------------------------------------------------
  Run:  powershell -ExecutionPolicy Bypass -File .\SantokuKnivesV14.ps1
  NEW IN v14
   * Bilingual buttons/labels: 日本語 (English) + hover tooltips
   * File-type search: extensions (wav mp3), "*" = all, or a preset
   * Name wildcard / regex, text-inside-file search, date newer/older
   * Fast multi-threaded scanner (UI never freezes, Esc = stop)
   * Duplicate finder (size -> quick hash -> SHA-1)
   * Sortable columns, multi-select, CSV export, drag & drop a folder
   * Built-in "C64 Terminal": a Commodore-DOS / BASIC V2 tribute.
       LOAD"$",8   LIST   DIR   FIND   EXT   GREP   BIG   DUPES ...
       10 PRINT "HELLO" : RUN     POKE 53280,2 changes the border!
   Hotkeys:  F5 = Slice   F2 = C64 Terminal   Esc = Stop / RUN-STOP

   This is a concept of Santuko Knives that Playfully adds Commodore
   Style CLI to the tool with basic programming adaptions
=====================================================================
#>

# WinForms wants STA. Relaunch ourselves if needed.
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $exe = (Get-Process -Id $PID).Path
    Start-Process -FilePath $exe -ArgumentList @('-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------------------------------------------------
#  C# engine: threaded slicer + BASIC V2 interpreter
# ---------------------------------------------------------------------
$csharp = @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

// ======================================================================
//  SLICER ENGINE  (background thread, no UI dependencies)
// ======================================================================
public class SliceHit
{
    public string FullName;
    public string Name;
    public string Ext;
    public string Dir;
    public long Length;
    public DateTime Modified;
    public string Extra = "";
}

public class SliceOptions
{
    public string Root;
    public string[] Extensions = new string[0];
    public string NamePattern = "";
    public bool UseRegex;
    public long MinBytes;
    public long MaxBytes = Int64.MaxValue;
    public bool UseDate;
    public DateTime DateValue;
    public bool DateNewer = true;
    public string ContentText = "";
    public bool IncludeHidden = true;
    public bool Recurse = true;
    public bool FindDupes;
    public long ContentMaxBytes = 64L * 1024 * 1024;
}

public class Slicer
{
    public volatile bool Cancel;
    public volatile bool Done;
    public long Scanned;
    public long Matched;
    public long DirsSeen;
    public volatile string CurrentDir = "";
    public volatile string Phase = "";
    public string Error = "";
    public List<SliceHit> Hits = new List<SliceHit>();
    private Thread worker;

    public void Start(SliceOptions o)
    {
        worker = new Thread(delegate() { Run(o); });
        worker.IsBackground = true;
        worker.Start();
    }

    private static Regex BuildNameRegex(SliceOptions o)
    {
        if (String.IsNullOrEmpty(o.NamePattern)) return null;
        string p = o.NamePattern;
        if (o.UseRegex) return new Regex(p, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        if (p.IndexOf('*') < 0 && p.IndexOf('?') < 0)
            return new Regex(Regex.Escape(p), RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        string body = Regex.Escape(p).Replace("\\*", ".*").Replace("\\?", ".");
        return new Regex("^" + body + "$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    }

    private void Run(SliceOptions o)
    {
        try
        {
            Regex nameRx = BuildNameRegex(o);
            Dictionary<string, bool> exts = null;
            if (o.Extensions != null && o.Extensions.Length > 0)
            {
                exts = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
                foreach (string e in o.Extensions) exts[e] = true;
            }
            string needle = null;
            if (!String.IsNullOrEmpty(o.ContentText))
                needle = Encoding.GetEncoding(28591).GetString(Encoding.UTF8.GetBytes(o.ContentText));

            Phase = "Scanning";
            Stack<string> stack = new Stack<string>();
            stack.Push(o.Root);
            while (stack.Count > 0 && !Cancel)
            {
                string dir = stack.Pop();
                CurrentDir = dir;
                DirsSeen++;
                DirectoryInfo di;
                FileInfo[] files;
                try
                {
                    di = new DirectoryInfo(dir);
                    files = di.GetFiles();
                }
                catch { continue; }

                foreach (FileInfo f in files)
                {
                    if (Cancel) break;
                    Scanned++;
                    try
                    {
                        if (Accept(f, o, exts, nameRx, needle))
                        {
                            SliceHit h = new SliceHit();
                            h.FullName = f.FullName;
                            h.Name = f.Name;
                            h.Ext = f.Extension.ToLowerInvariant();
                            h.Dir = f.DirectoryName;
                            h.Length = f.Length;
                            h.Modified = f.LastWriteTime;
                            Hits.Add(h);
                            Matched++;
                        }
                    }
                    catch { }
                }

                if (o.Recurse)
                {
                    try
                    {
                        foreach (DirectoryInfo sd in di.GetDirectories())
                        {
                            if ((sd.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                            stack.Push(sd.FullName);
                        }
                    }
                    catch { }
                }
            }
            if (o.FindDupes && !Cancel) FindDuplicates();
        }
        catch (Exception ex)
        {
            Error = ex.Message;
        }
        Done = true;
    }

    private bool Accept(FileInfo f, SliceOptions o, Dictionary<string, bool> exts, Regex rx, string needle)
    {
        if (!o.IncludeHidden && (f.Attributes & FileAttributes.Hidden) != 0) return false;
        long len = f.Length;
        if (len < o.MinBytes || len > o.MaxBytes) return false;
        if (exts != null && !exts.ContainsKey(f.Extension)) return false;
        if (rx != null && !rx.IsMatch(f.Name)) return false;
        if (o.UseDate)
        {
            if (o.DateNewer) { if (f.LastWriteTime < o.DateValue) return false; }
            else { if (f.LastWriteTime >= o.DateValue) return false; }
        }
        if (needle != null)
        {
            if (len == 0 || len > o.ContentMaxBytes) return false;
            if (!FileContains(f.FullName, needle)) return false;
        }
        return true;
    }

    private bool FileContains(string path, string needle)
    {
        try
        {
            Encoding enc = Encoding.GetEncoding(28591);
            using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read,
                   FileShare.ReadWrite | FileShare.Delete, 65536))
            {
                byte[] buf = new byte[1048576];
                string carry = "";
                int n;
                while ((n = fs.Read(buf, 0, buf.Length)) > 0)
                {
                    if (Cancel) return false;
                    string chunk = carry + enc.GetString(buf, 0, n);
                    if (chunk.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0) return true;
                    int keep = Math.Min(chunk.Length, needle.Length - 1);
                    carry = keep > 0 ? chunk.Substring(chunk.Length - keep) : "";
                }
            }
        }
        catch { }
        return false;
    }

    // ---- duplicate finder: size -> first 64KB hash -> full hash ----
    private void FindDuplicates()
    {
        Phase = "Grouping by size";
        Dictionary<long, List<SliceHit>> bySize = new Dictionary<long, List<SliceHit>>();
        foreach (SliceHit h in Hits)
        {
            if (h.Length <= 0) continue;
            List<SliceHit> l;
            if (!bySize.TryGetValue(h.Length, out l))
            {
                l = new List<SliceHit>();
                bySize[h.Length] = l;
            }
            l.Add(h);
        }
        List<SliceHit> result = new List<SliceHit>();
        foreach (KeyValuePair<long, List<SliceHit>> kv in bySize)
        {
            if (Cancel) break;
            if (kv.Value.Count < 2) continue;
            Dictionary<string, List<SliceHit>> quick = GroupByHash(kv.Value, 65536);
            foreach (List<SliceHit> qg in quick.Values)
            {
                if (Cancel) break;
                if (qg.Count < 2) continue;
                Dictionary<string, List<SliceHit>> full = GroupByHash(qg, -1);
                foreach (KeyValuePair<string, List<SliceHit>> fg in full)
                {
                    if (fg.Value.Count < 2) continue;
                    string tag = fg.Key.Substring(0, 8);
                    foreach (SliceHit h in fg.Value)
                    {
                        h.Extra = tag;
                        result.Add(h);
                    }
                }
            }
        }
        Hits = result;
        Matched = result.Count;
    }

    private Dictionary<string, List<SliceHit>> GroupByHash(List<SliceHit> src, int limit)
    {
        Dictionary<string, List<SliceHit>> d = new Dictionary<string, List<SliceHit>>();
        foreach (SliceHit h in src)
        {
            if (Cancel) break;
            Phase = "Hashing " + h.Name;
            string key = HashFile(h.FullName, limit);
            if (key == null) continue;
            List<SliceHit> l;
            if (!d.TryGetValue(key, out l))
            {
                l = new List<SliceHit>();
                d[key] = l;
            }
            l.Add(h);
        }
        return d;
    }

    private string HashFile(string path, int limit)
    {
        try
        {
            using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read,
                   FileShare.ReadWrite | FileShare.Delete, 65536))
            using (SHA1 sha = SHA1.Create())
            {
                byte[] hash;
                if (limit > 0)
                {
                    byte[] buf = new byte[limit];
                    int total = 0;
                    int n;
                    while (total < limit && (n = fs.Read(buf, total, limit - total)) > 0) total += n;
                    hash = sha.ComputeHash(buf, 0, total);
                }
                else
                {
                    hash = sha.ComputeHash(fs);
                }
                StringBuilder sb = new StringBuilder();
                foreach (byte b in hash) sb.Append(b.ToString("x2"));
                return sb.ToString();
            }
        }
        catch { return null; }
    }
}

// ======================================================================
//  BASIC V2-STYLE INTERPRETER  (tribute to the Commodore 64)
// ======================================================================
public class BasicError : Exception
{
    public BasicError(string m) : base(m) { }
}

public enum BasState { Idle, Running, Input, Ended, Error }

public class C64Basic
{
    public Action<string> Out;
    public Action<int, int> OnPoke;
    public Action OnReset;
    public SortedDictionary<int, string> Prog = new SortedDictionary<int, string>();
    public BasState State = BasState.Idle;
    public byte[] Mem = new byte[65536];
    public int Col;

    private class ForFrame { public string Var; public double Limit; public double Step; public int Li; public int Si; }
    private class ArrData { public int[] Dims; public object[] Data; }

    private Dictionary<string, object> vars = new Dictionary<string, object>();
    private Dictionary<string, ArrData> arrays = new Dictionary<string, ArrData>();
    private List<ForFrame> fors = new List<ForFrame>();
    private Stack<int[]> gosubs = new Stack<int[]>();
    private List<int> nums = new List<int>();
    private List<List<string>> stmts = new List<List<string>>();
    private Dictionary<int, int> lineIdx = new Dictionary<int, int>();
    private List<object> dataItems = new List<object>();
    private int dataPtr;
    private int li;
    private int si;
    private bool jumped;
    private string src = "";
    private int p;
    private StringBuilder outBuf = new StringBuilder();
    private List<string> inputNames = new List<string>();
    private List<string> inputBuf = new List<string>();
    private Random rnd = new Random();
    private int t0 = Environment.TickCount;

    private static readonly string[] Kw = {
        "PRINT", "INPUT", "GOSUB", "GOTO", "RETURN", "RESTORE", "READ", "DATA", "REM",
        "FOR", "NEXT", "END", "STOP", "DIM", "POKE", "SYS", "LET", "IF", "CLR" };
    private static readonly string[] Funcs = {
        "ABS", "INT", "SQR", "SIN", "COS", "TAN", "ATN", "LOG", "EXP", "SGN", "RND",
        "LEN", "VAL", "ASC", "CHR$", "STR$", "LEFT$", "RIGHT$", "MID$", "PEEK", "FRE", "POS" };

    public C64Basic()
    {
        Mem[53280] = 14;
        Mem[53281] = 6;
        Mem[646] = 14;
    }

    // ---------- public API ----------
    public void SetLine(int n, string text)
    {
        text = Normalize(text.Trim());
        if (text.Length == 0) Prog.Remove(n);
        else Prog[n] = text;
    }

    public void ClearProgram()
    {
        Prog.Clear();
        ClearVars();
        State = BasState.Idle;
    }

    public void Run()
    {
        ClearVars();
        Prepare(null);
        li = 0; si = 0;
        State = nums.Count == 0 ? BasState.Ended : BasState.Running;
    }

    public void Direct(string line)
    {
        fors.Clear();
        gosubs.Clear();
        Prepare(Normalize(line));
        li = 0; si = 0;
        State = BasState.Running;
    }

    public void Step(int budget)
    {
        try
        {
            while (State == BasState.Running && budget-- > 0)
            {
                while (li < nums.Count && si >= stmts[li].Count)
                {
                    if (nums[li] == -1) { State = BasState.Ended; return; }
                    li++; si = 0;
                }
                if (li >= nums.Count) { State = BasState.Ended; return; }
                jumped = false;
                try
                {
                    ExecText(stmts[li][si]);
                }
                catch (BasicError e) { Fail(e.Message); return; }
                catch (Exception) { Fail("SYNTAX"); return; }
                if (!jumped) si++;
                if (outBuf.Length > 4000) break;
            }
        }
        finally { Flush(); }
    }

    public void ProvideInput(string line)
    {
        if (State != BasState.Input) return;
        foreach (string part in line.Split(',')) inputBuf.Add(part.Trim());
        if (inputBuf.Count < inputNames.Count) { W("?? "); Flush(); return; }
        List<object> vals = new List<object>();
        bool ok = true;
        for (int i = 0; i < inputNames.Count; i++)
        {
            string nm = inputNames[i];
            string txt = inputBuf[i];
            if (nm.EndsWith("$")) { vals.Add(txt); continue; }
            double d = 0;
            if (txt.Length > 0 && !Double.TryParse(txt, NumberStyles.Float, CultureInfo.InvariantCulture, out d))
            {
                ok = false;
                break;
            }
            vals.Add(d);
        }
        inputBuf.Clear();
        if (!ok) { W("?REDO FROM START\n? "); Flush(); return; }
        for (int i = 0; i < inputNames.Count; i++) vars[inputNames[i]] = vals[i];
        State = BasState.Running;
    }

    public void Break()
    {
        if (State != BasState.Running && State != BasState.Input) return;
        if (Col != 0) W("\n");
        int ln = CurLine();
        W("BREAK" + (ln >= 0 ? " IN " + ln.ToString() : "") + "\n");
        State = BasState.Idle;
        Flush();
    }

    public void Flush()
    {
        if (outBuf.Length > 0 && Out != null)
        {
            string t = outBuf.ToString();
            outBuf.Length = 0;
            Out(t);
        }
    }

    // ---------- helpers ----------
    private int CurLine()
    {
        if (li >= 0 && li < nums.Count) return nums[li];
        return -1;
    }

    private void W(string s)
    {
        for (int i = 0; i < s.Length; i++)
        {
            char c = s[i];
            if (c == '\n') Col = 0;
            else if (c >= 32 && (c < 128 || c >= 160)) Col++;
        }
        outBuf.Append(s);
    }

    private void Fail(string msg)
    {
        State = BasState.Error;
        if (Col != 0) W("\n");
        int ln = CurLine();
        W("?" + msg + "  ERROR" + (ln >= 0 ? " IN " + ln.ToString() : "") + "\n");
    }

    private static BasicError Syn() { return new BasicError("SYNTAX"); }
    private static BasicError TypeMis() { return new BasicError("TYPE MISMATCH"); }
    private static BasicError Illegal() { return new BasicError("ILLEGAL QUANTITY"); }

    private void ClearVars()
    {
        vars.Clear();
        arrays.Clear();
        fors.Clear();
        gosubs.Clear();
        dataPtr = 0;
    }

    public static string Normalize(string line)
    {
        StringBuilder sb = new StringBuilder();
        bool q = false;
        foreach (char c in line)
        {
            if (c == '"') q = !q;
            sb.Append(q ? c : Char.ToUpperInvariant(c));
        }
        return sb.ToString();
    }

    private static List<string> SplitStatements(string line)
    {
        List<string> res = new List<string>();
        StringBuilder sb = new StringBuilder();
        bool q = false;
        foreach (char c in line)
        {
            if (c == '"') q = !q;
            if (c == ':' && !q)
            {
                string t = sb.ToString().TrimStart();
                if (t.StartsWith("REM", StringComparison.Ordinal)) { sb.Append(c); continue; }
                res.Add(sb.ToString());
                sb.Length = 0;
                continue;
            }
            sb.Append(c);
        }
        res.Add(sb.ToString());
        return res;
    }

    private void Prepare(string direct)
    {
        nums = new List<int>();
        stmts = new List<List<string>>();
        lineIdx = new Dictionary<int, int>();
        dataItems = new List<object>();
        if (direct != null)
        {
            nums.Add(-1);
            stmts.Add(SplitStatements(direct));
        }
        foreach (KeyValuePair<int, string> kv in Prog)
        {
            lineIdx[kv.Key] = nums.Count;
            nums.Add(kv.Key);
            List<string> sl = SplitStatements(Normalize(kv.Value));
            stmts.Add(sl);
            foreach (string s in sl)
            {
                string t = s.Trim();
                if (t.StartsWith("DATA", StringComparison.Ordinal)) CollectData(t.Substring(4));
            }
        }
    }

    private void CollectData(string body)
    {
        int i = 0;
        while (i <= body.Length)
        {
            while (i < body.Length && body[i] == ' ') i++;
            object item;
            if (i < body.Length && body[i] == '"')
            {
                int e = body.IndexOf('"', i + 1);
                string s;
                if (e < 0) { s = body.Substring(i + 1); i = body.Length; }
                else { s = body.Substring(i + 1, e - i - 1); i = e + 1; }
                item = s;
                while (i < body.Length && body[i] != ',') i++;
            }
            else
            {
                int e = body.IndexOf(',', i);
                string s;
                if (e < 0) { s = body.Substring(i); i = body.Length; }
                else { s = body.Substring(i, e - i); i = e; }
                s = s.Trim();
                double d;
                if (Double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out d)) item = d;
                else item = s;
            }
            dataItems.Add(item);
            if (i >= body.Length) break;
            i++;
        }
    }

    // ---------- lexer helpers over (src, p) ----------
    private void Ws() { while (p < src.Length && src[p] == ' ') p++; }
    private bool AtEnd() { Ws(); return p >= src.Length; }
    private char Pk() { Ws(); return p < src.Length ? src[p] : '\0'; }
    private bool Acc(char c) { if (Pk() == c) { p++; return true; } return false; }

    private bool AccWord(string w)
    {
        Ws();
        if (String.Compare(src, p, w, 0, w.Length, StringComparison.Ordinal) == 0)
        {
            int e = p + w.Length;
            if (e >= src.Length || !Char.IsLetter(src[e])) { p = e; return true; }
        }
        return false;
    }

    private string ReadIdent()
    {
        Ws();
        int s = p;
        while (p < src.Length && Char.IsLetterOrDigit(src[p])) p++;
        if (p < src.Length && (src[p] == '$' || src[p] == '%')) p++;
        return src.Substring(s, p - s);
    }

    // ---------- value helpers ----------
    private static double Num(object o)
    {
        if (o is double) return (double)o;
        throw TypeMis();
    }

    private static string Str(object o)
    {
        if (o is string) return (string)o;
        throw TypeMis();
    }

    private static string FmtCore(double d)
    {
        string s;
        if (d == Math.Floor(d) && Math.Abs(d) < 1e9) s = ((long)d).ToString(CultureInfo.InvariantCulture);
        else s = d.ToString("G9", CultureInfo.InvariantCulture);
        if (s.StartsWith("0.")) s = s.Substring(1);
        else if (s.StartsWith("-0.")) s = "-" + s.Substring(2);
        return (d >= 0 ? " " : "") + s;
    }

    // ---------- expression parser ----------
    private object ParseExpr() { return ParseOr(); }

    private object ParseOr()
    {
        object l = ParseAnd();
        while (AccWord("OR"))
        {
            object r = ParseAnd();
            l = (double)((long)Num(l) | (long)Num(r));
        }
        return l;
    }

    private object ParseAnd()
    {
        object l = ParseNot();
        while (AccWord("AND"))
        {
            object r = ParseNot();
            l = (double)((long)Num(l) & (long)Num(r));
        }
        return l;
    }

    private object ParseNot()
    {
        if (AccWord("NOT")) return (double)(~(long)Num(ParseNot()));
        return ParseCmp();
    }

    private int Compare(object a, object b)
    {
        if (a is string && b is string) return String.CompareOrdinal((string)a, (string)b);
        if (a is double && b is double) return ((double)a).CompareTo((double)b);
        throw TypeMis();
    }

    private object ParseCmp()
    {
        object l = ParseAdd();
        while (true)
        {
            Ws();
            string op = "";
            while (p < src.Length && (src[p] == '<' || src[p] == '>' || src[p] == '=') && op.Length < 2)
            {
                op += src[p];
                p++;
            }
            if (op.Length == 0) return l;
            object r = ParseAdd();
            int c = Compare(l, r);
            bool res;
            switch (op)
            {
                case "=": res = c == 0; break;
                case "<>": case "><": res = c != 0; break;
                case "<": res = c < 0; break;
                case ">": res = c > 0; break;
                case "<=": case "=<": res = c <= 0; break;
                case ">=": case "=>": res = c >= 0; break;
                default: throw Syn();
            }
            l = res ? -1.0 : 0.0;
        }
    }

    private object ParseAdd()
    {
        object l = ParseMul();
        while (true)
        {
            char c = Pk();
            if (c == '+')
            {
                p++;
                object r = ParseMul();
                if (l is string && r is string) l = (string)l + (string)r;
                else l = Num(l) + Num(r);
            }
            else if (c == '-')
            {
                p++;
                object r = ParseMul();
                l = Num(l) - Num(r);
            }
            else return l;
        }
    }

    private object ParseMul()
    {
        object l = ParseUnary();
        while (true)
        {
            char c = Pk();
            if (c == '*')
            {
                p++;
                object r = ParseUnary();
                l = Num(l) * Num(r);
            }
            else if (c == '/')
            {
                p++;
                object r = ParseUnary();
                double d = Num(r);
                if (d == 0) throw new BasicError("DIVISION BY ZERO");
                l = Num(l) / d;
            }
            else return l;
        }
    }

    private object ParseUnary()
    {
        char c = Pk();
        if (c == '-') { p++; return -Num(ParseUnary()); }
        if (c == '+') { p++; return ParseUnary(); }
        return ParsePow();
    }

    private object ParsePow()
    {
        object b = ParsePrimary();
        while (Pk() == '^')
        {
            p++;
            object e = ParseUnary();
            b = Math.Pow(Num(b), Num(e));
        }
        return b;
    }

    private object ParseNumber()
    {
        int s = p;
        while (p < src.Length && (Char.IsDigit(src[p]) || src[p] == '.')) p++;
        if (p < src.Length && src[p] == 'E' && p + 1 < src.Length &&
            (Char.IsDigit(src[p + 1]) ||
             ((src[p + 1] == '+' || src[p + 1] == '-') && p + 2 < src.Length && Char.IsDigit(src[p + 2]))))
        {
            p += 2;
            while (p < src.Length && Char.IsDigit(src[p])) p++;
        }
        double d;
        if (!Double.TryParse(src.Substring(s, p - s), NumberStyles.Float, CultureInfo.InvariantCulture, out d)) throw Syn();
        return d;
    }

    private object ParsePrimary()
    {
        char c = Pk();
        if (c == '(')
        {
            p++;
            object v = ParseExpr();
            if (!Acc(')')) throw Syn();
            return v;
        }
        if (c == '"')
        {
            p++;
            int e = src.IndexOf('"', p);
            string s;
            if (e < 0) { s = src.Substring(p); p = src.Length; }
            else { s = src.Substring(p, e - p); p = e + 1; }
            return s;
        }
        if (Char.IsDigit(c) || c == '.') return ParseNumber();
        if (Char.IsLetter(c))
        {
            string id = ReadIdent();
            if (Pk() == '(')
            {
                p++;
                List<object> args = new List<object>();
                if (!Acc(')'))
                {
                    do { args.Add(ParseExpr()); } while (Acc(','));
                    if (!Acc(')')) throw Syn();
                }
                if (Array.IndexOf(Funcs, id) >= 0) return CallFunc(id, args);
                ArrData a = GetArrayData(id, args.Count);
                return a.Data[ArrIndex(a, args)];
            }
            return GetVar(id);
        }
        throw Syn();
    }

    private object GetVar(string id)
    {
        switch (id)
        {
            case "TI": return (double)((long)(Environment.TickCount - t0) * 60L / 1000L);
            case "TI$": return DateTime.Now.ToString("HHmmss");
            case "ST": return 0.0;
            case "PI": return Math.PI;
        }
        object v;
        if (vars.TryGetValue(id, out v)) return v;
        if (id.EndsWith("$")) return "";
        return 0.0;
    }

    private static double ParseVal(string s)
    {
        Match m = Regex.Match(s, @"^\s*[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?");
        if (!m.Success) return 0.0;
        double d;
        if (Double.TryParse(m.Value, NumberStyles.Float, CultureInfo.InvariantCulture, out d)) return d;
        return 0.0;
    }

    private object CallFunc(string id, List<object> a)
    {
        if (a.Count < 1) throw Syn();
        switch (id)
        {
            case "ABS": return Math.Abs(Num(a[0]));
            case "INT": return Math.Floor(Num(a[0]));
            case "SQR":
                {
                    double x = Num(a[0]);
                    if (x < 0) throw Illegal();
                    return Math.Sqrt(x);
                }
            case "SIN": return Math.Sin(Num(a[0]));
            case "COS": return Math.Cos(Num(a[0]));
            case "TAN": return Math.Tan(Num(a[0]));
            case "ATN": return Math.Atan(Num(a[0]));
            case "LOG":
                {
                    double x = Num(a[0]);
                    if (x <= 0) throw Illegal();
                    return Math.Log(x);
                }
            case "EXP": return Math.Exp(Num(a[0]));
            case "SGN": return (double)Math.Sign(Num(a[0]));
            case "RND":
                {
                    double x = Num(a[0]);
                    if (x < 0) rnd = new Random((int)x);
                    return rnd.NextDouble();
                }
            case "LEN": return (double)Str(a[0]).Length;
            case "VAL": return ParseVal(Str(a[0]));
            case "ASC":
                {
                    string s = Str(a[0]);
                    if (s.Length == 0) throw Illegal();
                    return (double)(int)s[0];
                }
            case "CHR$":
                {
                    int n = (int)Num(a[0]);
                    if (n < 0 || n > 255) throw Illegal();
                    if (n == 13) return "\n";
                    return ((char)n).ToString();
                }
            case "STR$": return FmtCore(Num(a[0]));
            case "LEFT$":
                {
                    if (a.Count < 2) throw Syn();
                    string s = Str(a[0]);
                    int n = (int)Num(a[1]);
                    if (n < 0) throw Illegal();
                    return s.Substring(0, Math.Min(n, s.Length));
                }
            case "RIGHT$":
                {
                    if (a.Count < 2) throw Syn();
                    string s = Str(a[0]);
                    int n = (int)Num(a[1]);
                    if (n < 0) throw Illegal();
                    n = Math.Min(n, s.Length);
                    return s.Substring(s.Length - n);
                }
            case "MID$":
                {
                    if (a.Count < 2) throw Syn();
                    string s = Str(a[0]);
                    int st = (int)Num(a[1]);
                    if (st < 1) throw Illegal();
                    if (st > s.Length) return "";
                    int n = a.Count > 2 ? (int)Num(a[2]) : s.Length;
                    if (n < 0) throw Illegal();
                    n = Math.Min(n, s.Length - (st - 1));
                    return s.Substring(st - 1, n);
                }
            case "PEEK":
                {
                    int ad = (int)Num(a[0]);
                    if (ad < 0 || ad > 65535) throw Illegal();
                    return (double)Mem[ad];
                }
            case "FRE": return 38911.0;
            case "POS": return (double)Col;
        }
        throw Syn();
    }

    // ---------- arrays ----------
    private ArrData MakeArray(string id, int[] dims)
    {
        long total = 1;
        foreach (int d in dims)
        {
            if (d < 1) throw new BasicError("BAD SUBSCRIPT");
            total *= d;
            if (total > 1000000) throw new BasicError("OUT OF MEMORY");
        }
        ArrData a = new ArrData();
        a.Dims = dims;
        a.Data = new object[total];
        object def;
        if (id.EndsWith("$")) def = ""; else def = 0.0;
        for (int i = 0; i < a.Data.Length; i++) a.Data[i] = def;
        arrays[id] = a;
        return a;
    }

    private ArrData GetArrayData(string id, int nsubs)
    {
        ArrData a;
        if (!arrays.TryGetValue(id, out a))
        {
            int[] d = new int[nsubs];
            for (int i = 0; i < nsubs; i++) d[i] = 11;
            a = MakeArray(id, d);
        }
        if (a.Dims.Length != nsubs) throw new BasicError("BAD SUBSCRIPT");
        return a;
    }

    private int ArrIndex(ArrData a, List<object> subs)
    {
        int idx = 0;
        for (int i = 0; i < subs.Count; i++)
        {
            int s = (int)Num(subs[i]);
            if (s < 0 || s >= a.Dims[i]) throw new BasicError("BAD SUBSCRIPT");
            idx = idx * a.Dims[i] + s;
        }
        return idx;
    }

    // ---------- statements ----------
    private void ExecText(string t)
    {
        t = t.Trim();
        if (t.Length == 0) return;
        if (t[0] == '?') { src = t.Substring(1); p = 0; DoPrint(); return; }
        foreach (string k in Kw)
        {
            if (!t.StartsWith(k, StringComparison.Ordinal)) continue;
            src = t.Substring(k.Length);
            p = 0;
            switch (k)
            {
                case "PRINT": DoPrint(); break;
                case "INPUT": DoInput(); break;
                case "GOSUB": DoGosub(); break;
                case "GOTO": DoGoto(); break;
                case "RETURN": DoReturn(); break;
                case "RESTORE": dataPtr = 0; break;
                case "READ": DoRead(); break;
                case "DATA": break;
                case "REM": break;
                case "FOR": DoFor(); break;
                case "NEXT": DoNext(); break;
                case "END": State = BasState.Ended; break;
                case "STOP": Break(); break;
                case "DIM": DoDim(); break;
                case "POKE": DoPoke(); break;
                case "SYS": DoSys(); break;
                case "LET": DoAssign(); break;
                case "IF": DoIf(); break;
                case "CLR": ClearVars(); break;
            }
            return;
        }
        src = t;
        p = 0;
        DoAssign();
    }

    private void DoPrint()
    {
        bool nl = true;
        while (!AtEnd())
        {
            char c = Pk();
            if (c == ';') { p++; nl = false; continue; }
            if (c == ',')
            {
                p++;
                nl = false;
                int zone = ((Col / 10) + 1) * 10;
                W(new string(' ', zone - Col));
                continue;
            }
            if (AccWord("TAB"))
            {
                if (!Acc('(')) throw Syn();
                int n = (int)Num(ParseExpr());
                if (!Acc(')')) throw Syn();
                if (n > Col) W(new string(' ', n - Col));
                nl = true;
                continue;
            }
            if (AccWord("SPC"))
            {
                if (!Acc('(')) throw Syn();
                int n = (int)Num(ParseExpr());
                if (!Acc(')')) throw Syn();
                if (n > 0) W(new string(' ', n));
                nl = true;
                continue;
            }
            object v = ParseExpr();
            if (v is string) W((string)v);
            else W(FmtCore((double)v) + " ");
            nl = true;
        }
        if (nl) W("\n");
    }

    private void DoInput()
    {
        string prompt = "";
        if (Pk() == '"')
        {
            prompt = Str(ParsePrimary());
            Acc(';');
        }
        List<string> names = new List<string>();
        do
        {
            string id = ReadIdent();
            if (id.Length == 0) throw Syn();
            names.Add(id);
        } while (Acc(','));
        inputNames = names;
        inputBuf.Clear();
        W(prompt + "? ");
        State = BasState.Input;
    }

    private void JumpTo(int n)
    {
        int i;
        if (!lineIdx.TryGetValue(n, out i)) throw new BasicError("UNDEF'D STATEMENT");
        li = i;
        si = 0;
        jumped = true;
    }

    private void DoGoto() { JumpTo((int)Num(ParseExpr())); }

    private void DoGosub()
    {
        int n = (int)Num(ParseExpr());
        gosubs.Push(new int[] { li, si + 1 });
        JumpTo(n);
    }

    private void DoReturn()
    {
        if (gosubs.Count == 0) throw new BasicError("RETURN WITHOUT GOSUB");
        int[] r = gosubs.Pop();
        li = r[0];
        si = r[1];
        jumped = true;
    }

    private void DoFor()
    {
        string id = ReadIdent();
        if (id.Length == 0 || !Acc('=')) throw Syn();
        double start = Num(ParseExpr());
        if (!AccWord("TO")) throw Syn();
        double lim = Num(ParseExpr());
        double step = 1;
        if (AccWord("STEP")) step = Num(ParseExpr());
        vars[id] = start;
        fors.RemoveAll(f => f.Var == id);
        ForFrame fr = new ForFrame();
        fr.Var = id; fr.Limit = lim; fr.Step = step; fr.Li = li; fr.Si = si + 1;
        fors.Add(fr);
    }

    private void DoNext()
    {
        string id = null;
        if (!AtEnd()) id = ReadIdent();
        if (fors.Count == 0) throw new BasicError("NEXT WITHOUT FOR");
        int idx = fors.Count - 1;
        if (!String.IsNullOrEmpty(id))
        {
            string wanted = id;
            idx = fors.FindLastIndex(f => f.Var == wanted);
            if (idx < 0) throw new BasicError("NEXT WITHOUT FOR");
            fors.RemoveRange(idx + 1, fors.Count - idx - 1);
        }
        ForFrame fr = fors[idx];
        double v = Num(GetVar(fr.Var)) + fr.Step;
        vars[fr.Var] = v;
        bool cont = fr.Step >= 0 ? v <= fr.Limit : v >= fr.Limit;
        if (cont) { li = fr.Li; si = fr.Si; jumped = true; }
        else fors.RemoveAt(idx);
    }

    private void DoIf()
    {
        object c = ParseExpr();
        if (!AccWord("THEN") && !AccWord("GOTO")) throw Syn();
        bool truth = (c is string) ? ((string)c).Length > 0 : Num(c) != 0;
        if (!truth)
        {
            si = stmts[li].Count;
            jumped = true;
            return;
        }
        Ws();
        string rest = src.Substring(p).Trim();
        if (rest.Length > 0 && Char.IsDigit(rest[0]))
        {
            src = rest;
            p = 0;
            JumpTo((int)Num(ParseExpr()));
        }
        else ExecText(rest);
    }

    private void DoDim()
    {
        do
        {
            string id = ReadIdent();
            if (id.Length == 0 || !Acc('(')) throw Syn();
            List<int> dims = new List<int>();
            do { dims.Add((int)Num(ParseExpr()) + 1); } while (Acc(','));
            if (!Acc(')')) throw Syn();
            MakeArray(id, dims.ToArray());
        } while (Acc(','));
    }

    private void DoPoke()
    {
        int a = (int)Num(ParseExpr());
        if (!Acc(',')) throw Syn();
        int v = (int)Num(ParseExpr());
        if (a < 0 || a > 65535 || v < 0 || v > 255) throw Illegal();
        Mem[a] = (byte)v;
        if (OnPoke != null) OnPoke(a, v);
    }

    private void DoSys()
    {
        int a = (int)Num(ParseExpr());
        if (a == 64738 && OnReset != null)
        {
            Flush();
            OnReset();
        }
    }

    private void DoRead()
    {
        do
        {
            string id = ReadIdent();
            if (id.Length == 0) throw Syn();
            if (dataPtr >= dataItems.Count) throw new BasicError("OUT OF DATA");
            object item = dataItems[dataPtr++];
            if (id.EndsWith("$"))
            {
                if (item is string) vars[id] = item;
                else vars[id] = FmtCore((double)item).Trim();
            }
            else
            {
                if (!(item is double)) throw TypeMis();
                vars[id] = item;
            }
        } while (Acc(','));
    }

    private void DoAssign()
    {
        string id = ReadIdent();
        if (id.Length == 0) throw Syn();
        List<object> subs = null;
        if (Pk() == '(')
        {
            p++;
            subs = new List<object>();
            do { subs.Add(ParseExpr()); } while (Acc(','));
            if (!Acc(')')) throw Syn();
        }
        if (!Acc('=')) throw Syn();
        object v = ParseExpr();
        bool isStr = id.EndsWith("$");
        if (isStr != (v is string)) throw TypeMis();
        if (subs == null) vars[id] = v;
        else
        {
            ArrData a = GetArrayData(id, subs.Count);
            a.Data[ArrIndex(a, subs)] = v;
        }
    }
}
'@
if (-not ('Slicer' -as [type])) { Add-Type -TypeDefinition $csharp -Language CSharp }

# ---------------------------------------------------------------------
#  Theme
# ---------------------------------------------------------------------
$theme = @{
    Background = [System.Drawing.Color]::FromArgb(20, 20, 30)
    Panel      = [System.Drawing.Color]::FromArgb(30, 30, 44)
    Foreground = [System.Drawing.Color]::FromArgb(230, 230, 255)
    AccentNeon = [System.Drawing.Color]::FromArgb(0, 255, 255)
    AccentPink = [System.Drawing.Color]::FromArgb(255, 50, 150)
    AccentRed  = [System.Drawing.Color]::FromArgb(255, 100, 100)
    Highlight  = [System.Drawing.Color]::FromArgb(70, 70, 90)
    Font       = New-Object System.Drawing.Font('Consolas', 9)
    FontBold   = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
    FontTerm   = New-Object System.Drawing.Font('Consolas', 11, [System.Drawing.FontStyle]::Bold)
}

# Commodore 64 palette (Pepto), index 0-15
$c64Pal = @(
    [System.Drawing.Color]::FromArgb(0, 0, 0),       [System.Drawing.Color]::FromArgb(255, 255, 255),
    [System.Drawing.Color]::FromArgb(136, 57, 50),   [System.Drawing.Color]::FromArgb(103, 182, 189),
    [System.Drawing.Color]::FromArgb(139, 63, 150),  [System.Drawing.Color]::FromArgb(85, 160, 73),
    [System.Drawing.Color]::FromArgb(64, 49, 141),   [System.Drawing.Color]::FromArgb(191, 206, 114),
    [System.Drawing.Color]::FromArgb(139, 84, 41),   [System.Drawing.Color]::FromArgb(87, 66, 0),
    [System.Drawing.Color]::FromArgb(184, 105, 98),  [System.Drawing.Color]::FromArgb(80, 80, 80),
    [System.Drawing.Color]::FromArgb(120, 120, 120), [System.Drawing.Color]::FromArgb(148, 224, 137),
    [System.Drawing.Color]::FromArgb(120, 105, 196), [System.Drawing.Color]::FromArgb(159, 159, 159)
)
# PETSCII colour-code characters -> palette index (PRINT CHR$(28) etc.)
$script:PetColors = @{ 144 = 0; 5 = 1; 28 = 2; 159 = 3; 156 = 4; 30 = 5; 31 = 6; 158 = 7;
                       129 = 8; 149 = 9; 150 = 10; 151 = 11; 152 = 12; 153 = 13; 154 = 14; 155 = 15 }

# ---------------------------------------------------------------------
#  Global state
# ---------------------------------------------------------------------
$script:Results      = New-Object System.Collections.ArrayList
$script:SortCol      = 0
$script:SortAsc      = $false
$script:DisplayLimit = 25000
$script:Busy         = $false
$script:ActiveSlicer = $null
$script:TermList     = @()
$script:History      = New-Object System.Collections.ArrayList
$script:HistIdx      = 0
$script:ListMode     = 'prog'
$script:DirLines     = @()
$script:SkipReady    = $false
$script:TermFg       = $c64Pal[14]
$script:TermBuf      = New-Object System.Text.StringBuilder
try { $script:Cwd = (Get-Location).ProviderPath } catch { $script:Cwd = $env:USERPROFILE }
if (-not (Test-Path -LiteralPath $script:Cwd -PathType Container)) { $script:Cwd = $env:USERPROFILE }

# ---------------------------------------------------------------------
#  Small helpers
# ---------------------------------------------------------------------
function Format-Size([long]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
    return ('{0} B' -f $Bytes)
}

function ConvertTo-ExtList([string]$Text) {
    $out = @()
    foreach ($tok in ($Text -split '[,;\s]+')) {
        $t = $tok.Trim()
        if ($t -eq '') { continue }
        if ($t -eq '*' -or $t -eq '*.*') { return @() }
        $t = $t.TrimStart('*').TrimStart('.').ToLower()
        if ($t -ne '') { $out += ('.' + $t) }
    }
    return $out
}

function ConvertTo-WildRegex([string]$Pattern) {
    if ([string]::IsNullOrEmpty($Pattern) -or $Pattern -eq '*') { return '^.*$' }
    $body = [regex]::Escape($Pattern) -replace '\\\*', '.*' -replace '\\\?', '.'
    return '^' + $body + '$'
}

# ---------------------------------------------------------------------
#  Main form + layout
# ---------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = '💻 斬る File Slicer (ファイル・スライサー) 💻 v14'
$form.Size = New-Object System.Drawing.Size(1150, 830)
$form.MinimumSize = New-Object System.Drawing.Size(980, 680)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $theme.Background
$form.ForeColor = $theme.Foreground
$form.Font = $theme.Font
$form.KeyPreview = $true

$tip = New-Object System.Windows.Forms.ToolTip
$tip.InitialDelay = 250
$tip.AutoPopDelay = 12000
$tip.ShowAlways = $true

$inputPanel = New-Object System.Windows.Forms.Panel
$inputPanel.Dock = 'Top'
$inputPanel.Height = 196
$inputPanel.BackColor = $theme.Background

$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Dock = 'Bottom'
$statusPanel.Height = 30
$statusPanel.BackColor = $theme.Background

$txtStatus = New-Object System.Windows.Forms.TextBox
$txtStatus.Dock = 'Fill'
$txtStatus.ReadOnly = $true
$txtStatus.BackColor = $theme.Background
$txtStatus.ForeColor = $theme.AccentNeon
$txtStatus.Font = $theme.Font
$txtStatus.BorderStyle = 'None'
$txtStatus.Text = '準備完了 (Ready)... 🍣   F5 = Slice   F2 = C64 Terminal   Esc = Stop'
$statusPanel.Controls.Add($txtStatus)

$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = 'Fill'
$split.Orientation = 'Horizontal'
$split.SplitterWidth = 6
$split.BackColor = $theme.Highlight

# ---- results list ----------------------------------------------------
$lv = New-Object System.Windows.Forms.ListView
$lv.Dock = 'Fill'
$lv.View = 'Details'
$lv.FullRowSelect = $true
$lv.MultiSelect = $true
$lv.HideSelection = $false
$lv.BorderStyle = 'FixedSingle'
$lv.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 50)
$lv.ForeColor = $theme.Foreground
$lv.Font = $theme.Font
$lv.AllowDrop = $true
try {
    $dbp = $lv.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance,NonPublic')
    $dbp.SetValue($lv, $true, $null)
} catch { }
$right = [System.Windows.Forms.HorizontalAlignment]::Right
$left  = [System.Windows.Forms.HorizontalAlignment]::Left
[void]$lv.Columns.Add('サイズ (Size)', 105, $right)
[void]$lv.Columns.Add('更新日時 (Modified)', 140, $left)
[void]$lv.Columns.Add('種類 (Type)', 70, $left)
[void]$lv.Columns.Add('名前 (Name)', 270, $left)
[void]$lv.Columns.Add('フォルダ (Folder)', 520, $left)
[void]$lv.Columns.Add('備考 (Note)', 90, $left)
$split.Panel1.Controls.Add($lv)

# ---- C64 terminal ----------------------------------------------------
$termPanel = New-Object System.Windows.Forms.Panel
$termPanel.Dock = 'Fill'
$termPanel.Padding = New-Object System.Windows.Forms.Padding(26, 18, 26, 18)
$termPanel.BackColor = $c64Pal[14]

$termOut = New-Object System.Windows.Forms.RichTextBox
$termOut.Dock = 'Fill'
$termOut.ReadOnly = $true
$termOut.BorderStyle = 'None'
$termOut.BackColor = $c64Pal[6]
$termOut.ForeColor = $c64Pal[14]
$termOut.Font = $theme.FontTerm
$termOut.WordWrap = $true
$termOut.ScrollBars = 'Vertical'
$termOut.HideSelection = $false
$termOut.TabStop = $false
$termOut.Cursor = [System.Windows.Forms.Cursors]::IBeam

$termIn = New-Object System.Windows.Forms.TextBox
$termIn.Dock = 'Bottom'
$termIn.BorderStyle = 'None'
$termIn.BackColor = $c64Pal[6]
$termIn.ForeColor = [System.Drawing.Color]::White
$termIn.Font = $theme.FontTerm
$termIn.CharacterCasing = 'Upper'

$termPanel.Controls.Add($termOut)
$termPanel.Controls.Add($termIn)
$split.Panel2.Controls.Add($termPanel)

$form.Controls.Add($split)
$form.Controls.Add($inputPanel)
$form.Controls.Add($statusPanel)

# ---- input panel -----------------------------------------------------
$PaddingLeft = 20
$ButtonWidth = 160

$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Text = '対象フォルダ (Target Folder):'
$lblPath.Location = New-Object System.Drawing.Point($PaddingLeft, 10)
$lblPath.AutoSize = $true
$lblPath.ForeColor = $theme.AccentNeon
$inputPanel.Controls.Add($lblPath)

$txtPath = New-Object System.Windows.Forms.TextBox
$txtPath.Location = New-Object System.Drawing.Point($PaddingLeft, 32)
$txtPath.Width = 700
$txtPath.BorderStyle = 'FixedSingle'
$txtPath.BackColor = $theme.Background
$txtPath.ForeColor = $theme.AccentNeon
$txtPath.Anchor = 'Top, Left, Right'
$txtPath.AllowDrop = $true
$inputPanel.Controls.Add($txtPath)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = '参照 (Browse)...'
$btnBrowse.Size = New-Object System.Drawing.Size($ButtonWidth, 26)
$btnBrowse.FlatStyle = 'Flat'
$btnBrowse.FlatAppearance.BorderSize = 0
$btnBrowse.BackColor = $theme.AccentPink
$btnBrowse.ForeColor = $theme.Background
$btnBrowse.Anchor = 'Top, Right'
$inputPanel.Controls.Add($btnBrowse)

$filterPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$filterPanel.Location = New-Object System.Drawing.Point($PaddingLeft, 66)
$filterPanel.Height = 78
$filterPanel.Width = 1000
$filterPanel.FlowDirection = 'LeftToRight'
$filterPanel.WrapContents = $true
$filterPanel.Anchor = 'Top, Left, Right'
$inputPanel.Controls.Add($filterPanel)

$labelMargin = New-Object System.Windows.Forms.Padding(0, 8, 3, 0)
$boxMargin   = New-Object System.Windows.Forms.Padding(0, 5, 12, 0)

function Add-FilterLabel([string]$Text, $Color) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.AutoSize = $true
    $l.ForeColor = $Color
    $l.Margin = $labelMargin
    $filterPanel.Controls.Add($l)
    return $l
}
function Add-FilterBox([int]$Width, $Color) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Width = $Width
    $t.BorderStyle = 'FixedSingle'
    $t.Margin = $boxMargin
    $t.BackColor = $theme.Background
    $t.ForeColor = $Color
    $filterPanel.Controls.Add($t)
    return $t
}
function Add-FilterCheck([string]$Text, $Color) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text
    $c.AutoSize = $true
    $c.ForeColor = $Color
    $c.Margin = $labelMargin
    $filterPanel.Controls.Add($c)
    return $c
}
function Add-FilterCombo([int]$Width, [string[]]$Items) {
    $cb = New-Object System.Windows.Forms.ComboBox
    $cb.DropDownStyle = 'DropDownList'
    $cb.Width = $Width
    $cb.Margin = $boxMargin
    $cb.FlatStyle = 'Flat'
    $cb.BackColor = $theme.Background
    $cb.ForeColor = $theme.AccentNeon
    foreach ($i in $Items) { [void]$cb.Items.Add($i) }
    $cb.SelectedIndex = 0
    $filterPanel.Controls.Add($cb)
    return $cb
}

# row 1: file types / preset / name / regex / content
$lblTypes  = Add-FilterLabel '種類 (File Types):' $theme.AccentNeon
$txtTypes  = Add-FilterBox 150 $theme.AccentNeon
$txtTypes.Text = '*'
$cboPreset = Add-FilterCombo 190 @(
    'プリセット (Preset)...',
    'すべて (All Files) *',
    '音声 (Audio)',
    '動画 (Video)',
    '画像 (Images)',
    '文書 (Documents)',
    '圧縮 (Archives)',
    'コード (Code)',
    'DAW / FL Studio',
    'プラグイン (Plugins)',
    'コモドール (Commodore 64)')
$lblName   = Add-FilterLabel '名前 (Name):' $theme.AccentNeon
$txtName   = Add-FilterBox 150 $theme.AccentNeon
$chkRegex  = Add-FilterCheck '正規表現 (Regex)' $theme.AccentNeon
$lblText   = Add-FilterLabel '内容 (Contains Text):' $theme.AccentPink
$txtText   = Add-FilterBox 150 $theme.AccentPink

# row 2: size / date / options
$lblSizeMin = Add-FilterLabel '最小 (Min MB):' $theme.AccentPink
$txtSizeMin = Add-FilterBox 70 $theme.AccentPink
$lblSizeMax = Add-FilterLabel '最大 (Max MB):' $theme.AccentPink
$txtSizeMax = Add-FilterBox 70 $theme.AccentPink
$chkEnableDate = Add-FilterCheck '日付 (Date):' $theme.AccentNeon
$cboDate = Add-FilterCombo 150 @('以降 (Newer than)', '以前 (Older than)')
$cboDate.Enabled = $false
$dtpDate = New-Object System.Windows.Forms.DateTimePicker
$dtpDate.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$dtpDate.CustomFormat = 'yyyy-MM-dd'
$dtpDate.Size = New-Object System.Drawing.Size(115, 25)
$dtpDate.Margin = $boxMargin
$dtpDate.Enabled = $false
$dtpDate.CalendarTitleBackColor = $theme.Background
$dtpDate.CalendarTitleForeColor = $theme.AccentNeon
$filterPanel.Controls.Add($dtpDate)
$chkSub = Add-FilterCheck 'サブフォルダ (Subfolders)' $theme.AccentNeon
$chkSub.Checked = $true
$chkHidden = Add-FilterCheck '隠しファイル (Hidden)' $theme.AccentNeon
$chkHidden.Checked = $true

$chkEnableDate.Add_Click({
    $dtpDate.Enabled = $chkEnableDate.Checked
    $cboDate.Enabled = $chkEnableDate.Checked
})

# ---- button bar --------------------------------------------------------
$btnBar = New-Object System.Windows.Forms.FlowLayoutPanel
$btnBar.Location = New-Object System.Drawing.Point($PaddingLeft, 150)
$btnBar.Height = 38
$btnBar.Width = 1000
$btnBar.FlowDirection = 'LeftToRight'
$btnBar.WrapContents = $false
$btnBar.Anchor = 'Top, Left, Right'
$inputPanel.Controls.Add($btnBar)

function Add-BarButton([string]$Text, $Back, $Fore, [bool]$Bold) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.AutoSize = $true
    $b.AutoSizeMode = 'GrowAndShrink'
    $b.MinimumSize = New-Object System.Drawing.Size(110, 30)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $Back
    $b.ForeColor = $Fore
    $b.Margin = New-Object System.Windows.Forms.Padding(0, 3, 8, 3)
    if ($Bold) { $b.Font = $theme.FontBold }
    $btnBar.Controls.Add($b)
    return $b
}
$btnSearch = Add-BarButton '切断 (Slice) ❖' $theme.AccentNeon $theme.Background $true
$btnStop   = Add-BarButton '中止 (Stop)' $theme.AccentRed $theme.Background $false
$btnStop.Enabled = $false
$btnDupes  = Add-BarButton '重複 (Find Dupes)' $theme.AccentPink $theme.Background $false
$btnStats  = Add-BarButton '統計 (Stats)' $theme.Highlight $theme.Foreground $false
$btnExport = Add-BarButton '出力 (Export CSV)' $theme.Highlight $theme.Foreground $false
$btnTerm   = Add-BarButton '端末 (C64 Terminal)' ([System.Drawing.Color]::FromArgb(64, 49, 141)) ([System.Drawing.Color]::FromArgb(160, 150, 230)) $false

# ---- tooltips (English + 日本語) ---------------------------------------
$tip.SetToolTip($txtPath,    'Folder to search. You can also drag & drop a folder here.  検索するフォルダ (ドラッグ&ドロップ可)')
$tip.SetToolTip($btnBrowse,  'Choose the folder to slice.  フォルダを選択')
$tip.SetToolTip($txtTypes,   'File extensions, e.g.  wav mp3 flac   or   *   for all files.  拡張子 (* = すべて)')
$tip.SetToolTip($cboPreset,  'Quick presets for common file types.  よく使う種類のプリセット')
$tip.SetToolTip($txtName,    'File name filter. Wildcards * ? allowed; plain text = "contains".  ファイル名フィルタ')
$tip.SetToolTip($chkRegex,   'Treat the name filter as a regular expression.  名前を正規表現として扱う')
$tip.SetToolTip($txtText,    'Only files whose contents include this text (ASCII/UTF-8, files up to 64 MB).  ファイル内テキスト検索')
$tip.SetToolTip($txtSizeMin, 'Minimum file size in megabytes (decimals ok).  最小サイズ (MB)')
$tip.SetToolTip($txtSizeMax, 'Maximum file size in megabytes (decimals ok).  最大サイズ (MB)')
$tip.SetToolTip($chkEnableDate, 'Enable the modified-date filter.  更新日フィルタを有効化')
$tip.SetToolTip($cboDate,    'Newer than = modified on/after the date. Older than = before the date.  以降 / 以前')
$tip.SetToolTip($chkSub,     'Search inside subfolders too.  サブフォルダも検索')
$tip.SetToolTip($chkHidden,  'Include hidden files.  隠しファイルを含める')
$tip.SetToolTip($btnSearch,  'Run the search (F5).  検索開始')
$tip.SetToolTip($btnStop,    'Stop the running search (Esc).  検索を中止')
$tip.SetToolTip($btnDupes,   'Find duplicate files using the current filters (size, then hash).  重複ファイルを検索')
$tip.SetToolTip($btnStats,   'Show statistics of the current results in the terminal.  結果の統計を表示')
$tip.SetToolTip($btnExport,  'Save the current results to a CSV file.  結果をCSVに保存')
$tip.SetToolTip($btnTerm,    'Show / hide the Commodore-64 style terminal (F2).  C64端末の表示切替')
$tip.SetToolTip($lv,         'Click column headers to sort. Double-click opens a file. Right-click for more.  ヘッダーでソート / 右クリックメニュー')

function Update-Layout {
    $w = $inputPanel.ClientSize.Width
    $btnBrowse.Location = New-Object System.Drawing.Point(($w - $ButtonWidth - $PaddingLeft), 30)
    $txtPath.Width = $btnBrowse.Left - $PaddingLeft - 12
    $filterPanel.Width = $w - (2 * $PaddingLeft)
    $btnBar.Width = $w - (2 * $PaddingLeft)
}
$inputPanel.Add_Resize({ Update-Layout })

# ---------------------------------------------------------------------
#  Scanner glue
# ---------------------------------------------------------------------
function Set-BusyState([bool]$Busy) {
    $script:Busy = $Busy
    $btnSearch.Enabled = -not $Busy
    $btnDupes.Enabled  = -not $Busy
    $btnBrowse.Enabled = -not $Busy
    $btnStop.Enabled   = $Busy
}

function Invoke-Slicer($Options) {
    $sl = New-Object Slicer
    $script:ActiveSlicer = $sl
    Set-BusyState $true
    $spin = @('|', '/', '-', '\')
    $i = 0
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $sl.Start($Options)
    while (-not $sl.Done) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 35
        $i++
        if ($i % 3 -eq 0) {
            $where = $sl.CurrentDir
            if ($where.Length -gt 70) { $where = '...' + $where.Substring($where.Length - 67) }
            $txtStatus.Text = ('{0} 切断中 (Slicing)  スキャン (Scanned): {1:N0}  一致 (Matched): {2:N0}  [{3}]  {4}' -f `
                $spin[($i / 3) % 4], $sl.Scanned, $sl.Matched, $sl.Phase, $where)
        }
    }
    $sw.Stop()
    $script:LastElapsed = $sw.Elapsed.TotalSeconds
    $script:ActiveSlicer = $null
    Set-BusyState $false
    if ($sl.Error) { $txtStatus.Text = '❌ エラー (Error): ' + $sl.Error }
    return $sl
}

function Get-RowColor([long]$Bytes) {
    $mb = $Bytes / 1MB
    if ($mb -ge 1024) { return $theme.AccentRed }
    if ($mb -ge 500)  { return $theme.AccentPink }
    return $theme.AccentNeon
}

function Show-Results {
    $arr = @($script:Results)
    $props = @('Length', 'Modified', 'Ext', 'Name', 'Dir', 'Extra')
    if ($arr.Count -gt 1) {
        $arr = @($arr | Sort-Object -Property $props[$script:SortCol] -Descending:(-not $script:SortAsc))
    }
    $rows = New-Object 'System.Collections.Generic.List[System.Windows.Forms.ListViewItem]'
    $n = 0
    $total = 0L
    foreach ($h in $arr) {
        $total += $h.Length
        if ($n -lt $script:DisplayLimit) {
            $it = New-Object System.Windows.Forms.ListViewItem((Format-Size $h.Length))
            [void]$it.SubItems.Add($h.Modified.ToString('yyyy/MM/dd HH:mm'))
            [void]$it.SubItems.Add($h.Ext)
            [void]$it.SubItems.Add($h.Name)
            [void]$it.SubItems.Add($h.Dir)
            [void]$it.SubItems.Add($h.Extra)
            $it.Tag = $h
            $it.ForeColor = Get-RowColor $h.Length
            $rows.Add($it)
            $n++
        }
    }
    $lv.BeginUpdate()
    try {
        $lv.Items.Clear()
        $lv.Items.AddRange($rows.ToArray())
    } finally { $lv.EndUpdate() }
    $script:ShownTotal = $total
    $script:ShownCount = $arr.Count
}

function Set-Results($Hits) {
    $script:Results.Clear()
    if ($Hits -and @($Hits).Count -gt 0) { $script:Results.AddRange([object[]]@($Hits)) }
    Show-Results
}

function Get-SelectedHits {
    return @($lv.SelectedItems | ForEach-Object { $_.Tag })
}

function Get-GuiOptions {
    $path = $txtPath.Text.Trim().Trim('"')
    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Container)) {
        [void][System.Windows.Forms.MessageBox]::Show($form,
            "対象パスが無効です。`n(The target folder is invalid.)",
            'Error: Invalid Path', 'OK', 'Error')
        return $null
    }
    $o = New-Object SliceOptions
    $o.Root = $path
    $o.Extensions = [string[]]@(ConvertTo-ExtList $txtTypes.Text)
    $o.NamePattern = $txtName.Text.Trim()
    $o.UseRegex = $chkRegex.Checked
    $o.ContentText = $txtText.Text
    $o.Recurse = $chkSub.Checked
    $o.IncludeHidden = $chkHidden.Checked
    $min = $txtSizeMin.Text.Trim()
    $max = $txtSizeMax.Text.Trim()
    if ($min -match '^\d+(\.\d+)?$') { $o.MinBytes = [int64]([double]$min * 1MB) }
    if ($max -match '^\d+(\.\d+)?$') { $o.MaxBytes = [int64]([double]$max * 1MB) }
    if ($chkEnableDate.Checked) {
        $o.UseDate = $true
        $o.DateValue = $dtpDate.Value.Date
        $o.DateNewer = ($cboDate.SelectedIndex -eq 0)
    }
    if ($o.NamePattern -and $o.UseRegex) {
        try { [void][regex]::new($o.NamePattern) } catch {
            [void][System.Windows.Forms.MessageBox]::Show($form,
                "正規表現が無効です。`n(Invalid regular expression.)`n`n" + $_.Exception.Message, 'Regex Error', 'OK', 'Warning')
            return $null
        }
    }
    return $o
}

function Start-GuiSearch([bool]$Dupes) {
    if ($script:Busy) { return }
    $o = Get-GuiOptions
    if ($null -eq $o) { return }
    $o.FindDupes = $Dupes
    $sl = Invoke-Slicer $o
    $hits = @($sl.Hits)
    if ($Dupes) { $script:SortCol = 5; $script:SortAsc = $true } else { $script:SortCol = 0; $script:SortAsc = $false }
    Set-Results $hits
    $secs = '{0:N1}' -f $script:LastElapsed
    $extra = ''
    if ($Dupes -and $hits.Count -gt 0) {
        $wasted = 0L
        foreach ($g in ($hits | Group-Object -Property Extra)) { $wasted += [int64]$g.Group[0].Length * ($g.Count - 1) }
        $extra = ' | 無駄 (Wasted): ' + (Format-Size $wasted)
    }
    $cut = ''
    if ($script:ShownCount -gt $script:DisplayLimit) { $cut = " (表示 shown: $($script:DisplayLimit))" }
    $stopped = ''
    if ($sl.Cancel) { $stopped = ' ⚪ 中止 (Stopped)' }
    if (-not $sl.Error) {
        $txtStatus.Text = ('検索完了 (Done). {0:N0} 件 (files){1} | 合計 (Total): {2}{3} | {4}s | スキャン (Scanned): {5:N0}{6} 🍱' -f `
            $hits.Count, $cut, (Format-Size $script:ShownTotal), $extra, $secs, $sl.Scanned, $stopped)
    }
}

# ---------------------------------------------------------------------
#  Context menu actions
# ---------------------------------------------------------------------
function Open-Selected {
    $h = Get-SelectedHits
    if ($h.Count -eq 0) { return }
    try { Start-Process -FilePath $h[0].FullName } catch { $txtStatus.Text = '❌ エラー (Error): ' + $_.Exception.Message }
}

function Show-InFolder {
    $h = Get-SelectedHits
    if ($h.Count -eq 0) { return }
    Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"' + $h[0].FullName + '"')
}

function Copy-PathsToClipboard {
    $h = Get-SelectedHits
    if ($h.Count -eq 0) { return }
    [System.Windows.Forms.Clipboard]::SetText(($h | ForEach-Object { $_.FullName }) -join "`r`n")
    $txtStatus.Text = "📋 パスをコピー (Copied $($h.Count) path(s) to clipboard)"
}

function Copy-SelectedTo([bool]$Move) {
    $hits = Get-SelectedHits
    if ($hits.Count -eq 0) { return }
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($Move) { $dlg.Description = '移動先 (Select destination folder for MOVE):' }
    else { $dlg.Description = 'コピー先 (Select destination folder for COPY):' }
    if ($dlg.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) {
        $txtStatus.Text = '⚪ キャンセル (Cancelled).'
        return
    }
    $ok = 0; $bad = 0; $lastErr = ''
    foreach ($h in $hits) {
        try {
            if ($Move) { Move-Item -LiteralPath $h.FullName -Destination $dlg.SelectedPath -Force -ErrorAction Stop }
            else { Copy-Item -LiteralPath $h.FullName -Destination $dlg.SelectedPath -Force -ErrorAction Stop }
            $ok++
            if ($Move) { $script:Results.Remove($h) }
        } catch { $bad++; $lastErr = $_.Exception.Message }
    }
    if ($Move) { Show-Results }
    if ($bad -eq 0) { $txtStatus.Text = "✅ 完了 (Done): $ok file(s) -> $($dlg.SelectedPath)" }
    else { $txtStatus.Text = "⚠️ $ok ok, $bad failed. $lastErr" }
}

function Remove-SelectedToRecycleBin {
    $hits = Get-SelectedHits
    if ($hits.Count -eq 0) { return }
    $msg = "選択した $($hits.Count) 個のファイルをごみ箱に送りますか?`n(Send $($hits.Count) file(s) to the Recycle Bin?)`n`n" +
           (($hits | Select-Object -First 8 | ForEach-Object { $_.FullName }) -join "`n")
    if ($hits.Count -gt 8) { $msg += "`n... +$($hits.Count - 8) more" }
    $r = [System.Windows.Forms.MessageBox]::Show($form, $msg, 'Confirm Delete (削除の確認)', 'YesNo', 'Warning')
    if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { $txtStatus.Text = '⚪ キャンセル (Cancelled).'; return }
    $ok = 0; $bad = 0; $lastErr = ''
    foreach ($h in $hits) {
        try {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($h.FullName, 'OnlyErrorDialogs', 'SendToRecycleBin')
            $script:Results.Remove($h)
            $ok++
        } catch { $bad++; $lastErr = $_.Exception.Message }
    }
    Show-Results
    if ($bad -eq 0) { $txtStatus.Text = "✅ 削除完了 (Recycled): $ok file(s)." }
    else { $txtStatus.Text = "⚠️ $ok recycled, $bad failed. $lastErr" }
}

function Show-HashOfSelected {
    $h = Get-SelectedHits
    if ($h.Count -eq 0) { return }
    $txtStatus.Text = 'ハッシュ計算中 (Hashing)...'
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $form.Refresh()
    try {
        $r = Get-FileHash -LiteralPath $h[0].FullName -Algorithm SHA256 -ErrorAction Stop
        [System.Windows.Forms.Clipboard]::SetText($r.Hash)
        $txtStatus.Text = "SHA-256 $($h[0].Name): $($r.Hash)  (clipboard へコピー)"
    } catch { $txtStatus.Text = '❌ エラー (Error): ' + $_.Exception.Message }
    $form.Cursor = [System.Windows.Forms.Cursors]::Default
}

function Export-ResultsTo([string]$Path) {
    $script:Results | ForEach-Object {
        [pscustomobject]@{
            Path      = $_.FullName
            Name      = $_.Name
            Type      = $_.Ext
            SizeBytes = $_.Length
            SizeMB    = [math]::Round($_.Length / 1MB, 3)
            Modified  = $_.Modified.ToString('yyyy-MM-dd HH:mm:ss')
            Note      = $_.Extra
        }
    } | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
}

function Export-ResultsDialog {
    if ($script:Results.Count -eq 0) { $txtStatus.Text = '⚪ 出力する結果がありません (Nothing to export).'; return }
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = 'CSV (*.csv)|*.csv'
    $dlg.FileName = 'slice_results.csv'
    if ($dlg.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            Export-ResultsTo $dlg.FileName
            $txtStatus.Text = "✅ 出力完了 (Exported $($script:Results.Count) rows): $($dlg.FileName)"
        } catch { $txtStatus.Text = '❌ エラー (Error): ' + $_.Exception.Message }
    }
}

$ctx = New-Object System.Windows.Forms.ContextMenuStrip
$ctx.BackColor = $theme.Panel
$ctx.ForeColor = $theme.Foreground
function Add-MenuItem([string]$Text, [scriptblock]$Action) {
    $mi = New-Object System.Windows.Forms.ToolStripMenuItem($Text)
    $mi.Add_Click($Action)
    [void]$ctx.Items.Add($mi)
}
Add-MenuItem '開く (Open) 📂' { Open-Selected }
Add-MenuItem 'フォルダを表示 (Show in Folder)' { Show-InFolder }
Add-MenuItem 'パスをコピー (Copy Path) 📋' { Copy-PathsToClipboard }
[void]$ctx.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
Add-MenuItem 'コピー先... (Copy To...) 📁' { Copy-SelectedTo $false }
Add-MenuItem '移動先... (Move To...) ➡️' { Copy-SelectedTo $true }
Add-MenuItem 'SHA-256ハッシュ (Hash -> clipboard)' { Show-HashOfSelected }
[void]$ctx.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
Add-MenuItem 'ごみ箱へ (Move to Recycle Bin) 🗑️' { Remove-SelectedToRecycleBin }
$lv.ContextMenuStrip = $ctx
$ctx.Add_Opening({ param($s, $e) if ($lv.SelectedItems.Count -eq 0) { $e.Cancel = $true } })

$lv.Add_DoubleClick({ Open-Selected })
$lv.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq 'Return') { Open-Selected; $e.SuppressKeyPress = $true }
    elseif ($e.KeyCode -eq 'Delete') { Remove-SelectedToRecycleBin }
    elseif ($e.Control -and $e.KeyCode -eq 'C') { Copy-PathsToClipboard; $e.SuppressKeyPress = $true }
    elseif ($e.Control -and $e.KeyCode -eq 'A') { foreach ($i in $lv.Items) { $i.Selected = $true } }
})
$lv.Add_ColumnClick({
    param($s, $e)
    if ($script:SortCol -eq $e.Column) { $script:SortAsc = -not $script:SortAsc }
    else { $script:SortCol = $e.Column; $script:SortAsc = ($e.Column -ge 2) }
    Show-Results
})

# ---------------------------------------------------------------------
#  Button + control events
# ---------------------------------------------------------------------
$btnBrowse.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = '切るフォルダを選択 (Select the folder to slice)...'
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) { $txtPath.Text = $dialog.SelectedPath }
})
$btnSearch.Add_Click({ Start-GuiSearch $false })
$btnDupes.Add_Click({ Start-GuiSearch $true })
$btnStop.Add_Click({ if ($script:ActiveSlicer) { $script:ActiveSlicer.Cancel = $true } })
$btnExport.Add_Click({ Export-ResultsDialog })
$btnStats.Add_Click({
    if ($split.Panel2Collapsed) { $split.Panel2Collapsed = $false }
    Submit-Term 'STATS'
})
$btnTerm.Add_Click({ Switch-Terminal })

$cboPreset.Add_SelectedIndexChanged({
    switch ($cboPreset.SelectedIndex) {
        1  { $txtTypes.Text = '*' }
        2  { $txtTypes.Text = 'wav mp3 flac ogg aiff aif m4a wma opus mid midi' }
        3  { $txtTypes.Text = 'mp4 mkv avi mov wmv webm flv m4v' }
        4  { $txtTypes.Text = 'jpg jpeg png gif bmp tif tiff webp svg psd ico' }
        5  { $txtTypes.Text = 'pdf doc docx xls xlsx ppt pptx txt rtf md odt csv' }
        6  { $txtTypes.Text = 'zip rar 7z tar gz bz2 xz iso cab' }
        7  { $txtTypes.Text = 'c cpp h hpp cs py js ts ps1 java rs asm bas lua json xml html css' }
        8  { $txtTypes.Text = 'flp fst wav mid syx' }
        9  { $txtTypes.Text = 'vst3 vst clap' }
        10 { $txtTypes.Text = 'prg d64 d71 d81 t64 tap crt sid p00 seq' }
    }
})

$txtPath.Add_TextChanged({
    $p = $txtPath.Text.Trim().Trim('"')
    if ($p -and (Test-Path -LiteralPath $p -PathType Container)) { $script:Cwd = (Resolve-Path -LiteralPath $p).ProviderPath }
})

# drag & drop a folder (or a file -> its folder)
foreach ($c in @($form, $lv, $inputPanel, $txtPath)) {
    $c.AllowDrop = $true
    $c.Add_DragEnter({
        param($s, $e)
        if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
            $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy
        }
    })
    $c.Add_DragDrop({
        param($s, $e)
        $p = @($e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop))[0]
        if (Test-Path -LiteralPath $p -PathType Leaf) { $p = Split-Path -Parent $p }
        $txtPath.Text = $p
    })
}

function Switch-Terminal {
    $split.Panel2Collapsed = -not $split.Panel2Collapsed
    if (-not $split.Panel2Collapsed) { $termIn.Focus() }
}

$form.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq 'F5') { $e.SuppressKeyPress = $true; Start-GuiSearch $false }
    elseif ($e.KeyCode -eq 'F2') { $e.SuppressKeyPress = $true; Switch-Terminal }
    elseif ($e.KeyCode -eq 'Escape' -and $script:Busy -and $script:ActiveSlicer) { $script:ActiveSlicer.Cancel = $true }
})

# =====================================================================
#  C64 TERMINAL  --  Commodore DOS + BASIC V2 tribute
# =====================================================================
$basic = New-Object C64Basic

function Send-TermBuf {
    if ($script:TermBuf.Length -eq 0) { return }
    $termOut.SelectionStart = $termOut.TextLength
    $termOut.SelectionLength = 0
    $termOut.SelectionColor = $script:TermFg
    $termOut.AppendText($script:TermBuf.ToString())
    [void]$script:TermBuf.Clear()
}

function Write-Term([string]$Text) {
    if ($termOut.TextLength -gt 300000) { $termOut.Clear() }
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int]$ch
        if ($code -eq 10 -or ($code -ge 32 -and $code -lt 128) -or $code -ge 160) {
            [void]$script:TermBuf.Append($ch)
            continue
        }
        if ($code -eq 13) { continue }
        Send-TermBuf
        if ($code -eq 147) { $termOut.Clear() }
        elseif ($script:PetColors.ContainsKey($code)) { $script:TermFg = $c64Pal[$script:PetColors[$code]] }
    }
    Send-TermBuf
    $termOut.SelectionStart = $termOut.TextLength
    $termOut.ScrollToCaret()
}

function Write-Ready { Write-Term "READY.`n" }

function Reset-Term {
    $script:SkipReady = $true
    $pump.Stop()
    $basic.ClearProgram()
    $basic.Col = 0
    $script:ListMode = 'prog'
    $script:DirLines = @()
    $termPanel.BackColor = $c64Pal[14]
    $termOut.BackColor = $c64Pal[6]
    $termIn.BackColor = $c64Pal[6]
    $script:TermFg = $c64Pal[14]
    $termOut.Clear()
    Write-Term "`n    **** FILE SLICER 64 BASIC V2 ****`n`n 64K RAM SYSTEM  38911 BASIC BYTES FREE`n`n"
    Write-Term "TYPE HELP FOR COMMANDS. LOAD`"`$`",8 THEN LIST`n`n"
    Write-Ready
}

$basic.Out = [Action[string]]{ param($s) Write-Term $s }
$basic.OnReset = [Action]{ Reset-Term }
$basic.OnPoke = [Action[int, int]]{
    param($a, $v)
    $col = $c64Pal[$v -band 15]
    switch ($a) {
        53280 { $termPanel.BackColor = $col }
        53281 { $termOut.BackColor = $col; $termIn.BackColor = $col }
        646   { $script:TermFg = $col }
    }
}

# BASIC run-loop pump
$pump = New-Object System.Windows.Forms.Timer
$pump.Interval = 15
$pump.Add_Tick({
    $pump.Stop()
    $basic.Step(2500)
    $st = $basic.State.ToString()
    if ($st -eq 'Running') { $pump.Start(); return }
    if ($st -eq 'Input') { return }
    if ($script:SkipReady) { $script:SkipReady = $false; return }
    if ($basic.Col -ne 0) { Write-Term "`n" }
    $basic.Col = 0
    Write-Ready
})

# ---- disk-style directory listing -----------------------------------
function Get-DirLines([string]$Pattern) {
    $rx = ConvertTo-WildRegex $Pattern
    $name = Split-Path -Leaf $script:Cwd
    if (-not $name) { $name = $script:Cwd.TrimEnd('\') }
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add(('0'.PadRight(5) + '"' + $name.ToUpper().PadRight(16) + '" SL 2A'))
    $items = Get-ChildItem -LiteralPath $script:Cwd -Force -ErrorAction SilentlyContinue |
             Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name
    foreach ($it in $items) {
        if (-not [regex]::IsMatch($it.Name, $rx, 'IgnoreCase')) { continue }
        if ($it.PSIsContainer) { $blocks = 0; $type = 'DIR' }
        else { $blocks = [int64][math]::Ceiling($it.Length / 254.0); $type = 'PRG' }
        [void]$lines.Add(([string]$blocks).PadRight(5) + '"' + $it.Name.ToUpper().PadRight(16) + '"  ' + $type)
    }
    $free = 664
    try {
        $root = [System.IO.Path]::GetPathRoot($script:Cwd)
        $free = [int64]([System.IO.DriveInfo]::new($root).AvailableFreeSpace / 254)
    } catch { }
    [void]$lines.Add("$free BLOCKS FREE.")
    return @($lines)
}

# ---- option parsing for terminal search commands --------------------
function Set-OptKey($O, [string]$Key, [string]$Val) {
    switch ($Key) {
        'name'   { $O.NamePattern = $Val }
        'ext'    { $O.Extensions = [string[]]@(ConvertTo-ExtList $Val) }
        'type'   { $O.Extensions = [string[]]@(ConvertTo-ExtList $Val) }
        'min'    { $O.MinBytes = [int64]([double]$Val * 1MB) }
        'max'    { $O.MaxBytes = [int64]([double]$Val * 1MB) }
        'text'   { $O.ContentText = $Val }
        'grep'   { $O.ContentText = $Val }
        'newer'  { $O.UseDate = $true; $O.DateNewer = $true;  $O.DateValue = (Get-Date).Date.AddDays(-[double]$Val) }
        'older'  { $O.UseDate = $true; $O.DateNewer = $false; $O.DateValue = (Get-Date).Date.AddDays(-[double]$Val) }
        'sub'    { $O.Recurse = ($Val -ne '0') }
        'hidden' { $O.IncludeHidden = ($Val -ne '0') }
        default  { throw "UNKNOWN OPTION $Key" }
    }
}

function New-TermOptions([string]$Arg, [string]$DefaultKey) {
    $o = New-Object SliceOptions
    $o.Root = $script:Cwd
    $usedBare = $false
    foreach ($tok in ($Arg -split '\s+')) {
        if ($tok -eq '') { continue }
        if ($tok -match '^([A-Za-z]+)=(.*)$') {
            $k = $Matches[1].ToLower()
            $v = $Matches[2]
            Set-OptKey $o $k $v
        } elseif (-not $usedBare -and $DefaultKey) {
            Set-OptKey $o $DefaultKey $tok
            $usedBare = $true
        } else { throw 'SYNTAX' }
    }
    return $o
}

function Show-TermHits($Hits, [int]$Top) {
    $sorted = @($Hits | Sort-Object -Property Length -Descending)
    $script:TermList = $sorted
    $sb = New-Object System.Text.StringBuilder
    $n = 0
    foreach ($h in ($sorted | Select-Object -First $Top)) {
        $n++
        [void]$sb.Append(('{0,3} {1,10} {2}' -f $n, (Format-Size $h.Length), $h.FullName.ToUpper()) + "`n")
    }
    if ($n -gt 0) { Write-Term $sb.ToString() }
    if ($sorted.Count -gt $n) { Write-Term ("... +{0} MORE (SEE LIST ABOVE)`n" -f ($sorted.Count - $n)) }
}

function Invoke-TermSlice($Opts, [int]$Top, [bool]$Dupes) {
    $Opts.FindDupes = $Dupes
    Write-Term ('SEARCHING ' + $Opts.Root.ToUpper() + "`n")
    $sl = Invoke-Slicer $Opts
    $hits = @($sl.Hits)
    if ($Dupes) { $script:SortCol = 5; $script:SortAsc = $true } else { $script:SortCol = 0; $script:SortAsc = $false }
    Set-Results $hits
    Show-TermHits $hits $Top
    if ($sl.Error) { Write-Term ('?' + $sl.Error.ToUpper() + "  ERROR`n") }
    Write-Term ("{0} FILES FOUND. ({1} SCANNED, {2:N1}S)`n" -f $hits.Count, $sl.Scanned, $script:LastElapsed)
    $txtStatus.Text = ('✅ Terminal search: {0:N0} files | {1}' -f $hits.Count, (Format-Size $script:ShownTotal))
}

function Invoke-TermStats {
    $arr = @($script:Results)
    if ($arr.Count -eq 0) { Write-Term "?NO RESULTS  ERROR`n"; return }
    $groups = @($arr | Group-Object -Property Ext | ForEach-Object {
        $sum = ($_.Group | Measure-Object -Property Length -Sum).Sum
        [pscustomobject]@{ Ext = $_.Name; Count = $_.Count; Bytes = [int64]$sum }
    } | Sort-Object -Property Bytes -Descending | Select-Object -First 15)
    $max = ($groups | Measure-Object -Property Bytes -Maximum).Maximum
    if (-not $max) { $max = 1 }
    Write-Term "EXTENSION STATISTICS`n"
    foreach ($g in $groups) {
        $label = $g.Ext.ToUpper()
        if (-not $label) { $label = '(NONE)' }
        $bar = '█' * [math]::Max(1, [int](18 * $g.Bytes / $max))
        Write-Term (('{0,-8} {1,6} {2,10} {3}' -f $label, $g.Count, (Format-Size $g.Bytes), $bar) + "`n")
    }
    $tot = ($arr | Measure-Object -Property Length -Sum).Sum
    Write-Term ("{0} FILES, {1}`n" -f $arr.Count, (Format-Size ([int64]$tot)))
}

function Invoke-TermLoad([string]$Arg) {
    if ($Arg -notmatch '^\s*"([^"]*)"?') { Write-Term "?SYNTAX  ERROR`n"; return }
    $name = $Matches[1]
    Write-Term ('SEARCHING FOR ' + $name + "`nLOADING`n")
    if ($name.StartsWith('$')) {
        $pat = $name.Substring(1).TrimStart(':')
        if ($pat -match '^\d*:(.*)$') { $pat = $Matches[1] }
        $script:DirLines = Get-DirLines $pat
        $script:ListMode = 'dir'
        $basic.Prog.Clear()
        return
    }
    $path = $null
    if ($name -match '[*?]') {
        $rx = ConvertTo-WildRegex $name
        $hit = Get-ChildItem -LiteralPath $script:Cwd -File -ErrorAction SilentlyContinue |
               Where-Object { [regex]::IsMatch($_.Name, $rx, 'IgnoreCase') } | Select-Object -First 1
        if ($hit) { $path = $hit.FullName }
    } else {
        $cand = Join-Path $script:Cwd $name
        if (Test-Path -LiteralPath $cand -PathType Leaf) { $path = $cand }
    }
    if (-not $path) { Write-Term "?FILE NOT FOUND  ERROR`n"; return }
    if ((Get-Item -LiteralPath $path).Length -gt 1MB) { Write-Term "?FILE TOO LARGE  ERROR`n"; return }
    $basic.Prog.Clear()
    $cnt = 0
    foreach ($ln in (Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
        if ($ln -match '^\s*(\d+)\s*(.*)$') { $basic.SetLine([int]$Matches[1], $Matches[2]); $cnt++ }
    }
    if ($cnt -eq 0) { Write-Term "?NOT A BASIC TEXT FILE  ERROR`n"; return }
    $script:ListMode = 'prog'
    $script:DirLines = @()
}

function Invoke-TermSave([string]$Arg) {
    if ($Arg -notmatch '^\s*"([^"]*)"?') { Write-Term "?SYNTAX  ERROR`n"; return }
    $name = $Matches[1]
    $overwrite = $false
    if ($name -match '^@\d*:(.*)$') { $overwrite = $true; $name = $Matches[1] }
    if (-not $name) { Write-Term "?MISSING FILE NAME  ERROR`n"; return }
    if (-not [System.IO.Path]::GetExtension($name)) { $name += '.bas' }
    $path = Join-Path $script:Cwd $name
    if ((Test-Path -LiteralPath $path) -and -not $overwrite) { Write-Term "?FILE EXISTS  ERROR`n(USE SAVE`"@:NAME`",8 TO REPLACE)`n"; return }
    $out = foreach ($k in @($basic.Prog.Keys)) { '{0} {1}' -f $k, $basic.Prog[$k] }
    Set-Content -LiteralPath $path -Value $out -Encoding ASCII
    Write-Term ('SAVING ' + $name.ToUpper() + "`n")
}

$script:HelpText = @'
COMMODORE-DOS STYLE
 LOAD"$",8      LOAD DIRECTORY, THEN LIST
 LOAD"*.WAV",8  LOAD DIR WITH A PATTERN
 DIR [PAT]      SHOW FOLDER  CD PATH / CD ..
SEARCH (RECURSIVE FROM CURRENT FOLDER)
 FIND *MIX*     BY NAME        EXT WAV MP3
 GREP TEXT      INSIDE FILES   BIG 20 LARGEST
 NEWER 7        LAST 7 DAYS    OLDER 365
 DUPES          DUPLICATE FILES
 SLICE EXT=WAV MIN=5 MAX=500 NAME=*MIX* TEXT=X
        NEWER=30 OLDER=90 SUB=0 HIDDEN=0
RESULTS
 STATS  SIZE  OPEN 3  EXPLORE 3  EXPORT [FILE]
BASIC V2
 10 PRINT "HELLO"   RUN   LIST   NEW
 SAVE"X.BAS",8  LOAD"X.BAS",8
 POKE 53280,2 BORDER  POKE 53281,0 BACKGROUND
 PRINT CHR$(147) CLEAR  CHR$(28) RED  CHR$(5) WHITE
 SYS 64738 RESET     ESC = RUN/STOP
'@

function Invoke-TermCommand([string]$Line) {
    $t = $Line.Trim()
    if ($basic.State.ToString() -eq 'Input') {
        Write-Term ($t + "`n")
        $basic.ProvideInput($t)
        $pump.Start()
        return
    }
    Write-Term ($t + "`n")
    if ($t -eq '') { return }

    if ($t -match '^(\d+)\s*(.*)$') {
        $script:ListMode = 'prog'
        $script:DirLines = @()
        $basic.SetLine([int]$Matches[1], $Matches[2])
        return
    }

    $cmd = ''
    $arg = ''
    if ($t -match '^([A-Za-z]+)(.*)$') { $cmd = $Matches[1].ToUpper(); $arg = $Matches[2].Trim() }

    switch ($cmd) {
        'HELP'  { Write-Term ($script:HelpText -replace "`r", '') ; Write-Term "`n"; Write-Ready; return }
        'CLS'   { Write-Term ([string][char]147); Write-Ready; return }
        'RESET' { Reset-Term; return }
        'EXIT'  { $split.Panel2Collapsed = $true; return }
        'QUIT'  { $split.Panel2Collapsed = $true; return }
        'PWD'   { Write-Term ($script:Cwd.ToUpper() + "`n"); Write-Ready; return }
        'CD' {
            if ($arg -eq '') { Write-Term ($script:Cwd.ToUpper() + "`n"); Write-Ready; return }
            $arg = $arg.Trim('"')
            $target = $null
            if ($arg -eq '..') { $target = Split-Path -Parent $script:Cwd }
            elseif ([System.IO.Path]::IsPathRooted($arg)) { $target = $arg }
            else { $target = Join-Path $script:Cwd $arg }
            if ($target -and (Test-Path -LiteralPath $target -PathType Container)) {
                $txtPath.Text = (Resolve-Path -LiteralPath $target).ProviderPath
                Write-Term ($script:Cwd.ToUpper() + "`n")
            } else { Write-Term "?PATH NOT FOUND  ERROR`n" }
            Write-Ready
            return
        }
        'DIR' {
            $lines = Get-DirLines $arg
            Write-Term (($lines -join "`n") + "`n")
            Write-Ready
            return
        }
        'LOAD' { Invoke-TermLoad $arg; Write-Ready; return }
        'SAVE' { Invoke-TermSave $arg; Write-Ready; return }
        'LIST' {
            if ($script:ListMode -eq 'dir') { Write-Term (($script:DirLines -join "`n") + "`n") }
            else {
                $sb = New-Object System.Text.StringBuilder
                foreach ($k in @($basic.Prog.Keys)) { [void]$sb.Append(('{0} {1}' -f $k, $basic.Prog[$k]) + "`n") }
                Write-Term $sb.ToString()
            }
            Write-Ready
            return
        }
        'NEW' {
            $basic.ClearProgram()
            $script:ListMode = 'prog'
            $script:DirLines = @()
            Write-Ready
            return
        }
        'RUN' {
            if ($script:ListMode -eq 'dir') { Write-Term "?SYNTAX  ERROR`n"; Write-Ready; return }
            $basic.Col = 0
            $basic.Run()
            $pump.Start()
            return
        }
        'FIND' {
            Invoke-TermSlice (New-TermOptions $arg 'name') 40 $false
            Write-Ready
            return
        }
        'EXT' {
            if ($arg -notmatch '=') { $arg = 'ext=' + ($arg -replace '\s+', ',') }
            Invoke-TermSlice (New-TermOptions $arg 'ext') 40 $false
            Write-Ready
            return
        }
        'GREP' {
            Invoke-TermSlice (New-TermOptions $arg 'text') 40 $false
            Write-Ready
            return
        }
        'NEWER' {
            Invoke-TermSlice (New-TermOptions $arg 'newer') 40 $false
            Write-Ready
            return
        }
        'OLDER' {
            Invoke-TermSlice (New-TermOptions $arg 'older') 40 $false
            Write-Ready
            return
        }
        'SLICE' {
            Invoke-TermSlice (New-TermOptions $arg '') 40 $false
            Write-Ready
            return
        }
        'DUPES' {
            Invoke-TermSlice (New-TermOptions $arg '') 60 $true
            Write-Ready
            return
        }
        'BIG' {
            $n = 20
            if ($arg -match '^\d+') { $n = [int]$Matches[0] }
            Invoke-TermSlice (New-TermOptions '' '') $n $false
            Write-Ready
            return
        }
        'STATS' { Invoke-TermStats; Write-Ready; return }
        'SIZE' {
            $o = New-TermOptions $arg ''
            $sl = Invoke-Slicer $o
            $tot = 0L
            foreach ($h in $sl.Hits) { $tot += $h.Length }
            Write-Term ("{0:N0} FILES, {1}, {2:N0} BLOCKS`n" -f $sl.Hits.Count, (Format-Size $tot), [math]::Ceiling($tot / 254.0))
            Write-Ready
            return
        }
        'OPEN' {
            $i = [int]$arg
            if ($i -ge 1 -and $i -le @($script:TermList).Count) { Start-Process -FilePath @($script:TermList)[$i - 1].FullName }
            else { Write-Term "?ILLEGAL QUANTITY  ERROR`n" }
            Write-Ready
            return
        }
        'EXPLORE' {
            $i = [int]$arg
            if ($i -ge 1 -and $i -le @($script:TermList).Count) {
                Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"' + @($script:TermList)[$i - 1].FullName + '"')
            } else { Write-Term "?ILLEGAL QUANTITY  ERROR`n" }
            Write-Ready
            return
        }
        'EXPORT' {
            if ($script:Results.Count -eq 0) { Write-Term "?NO RESULTS  ERROR`n"; Write-Ready; return }
            $f = $arg.Trim('"')
            if (-not $f) { $f = 'slice_results.csv' }
            if (-not [System.IO.Path]::IsPathRooted($f)) { $f = Join-Path $script:Cwd $f }
            Export-ResultsTo $f
            Write-Term ('SAVED ' + $script:Results.Count + ' ROWS TO ' + $f.ToUpper() + "`n")
            Write-Ready
            return
        }
    }

    # anything else: a BASIC statement
    $basic.Col = 0
    $basic.Direct($t)
    $pump.Start()
}

function Submit-Term([string]$Line) {
    $st = $basic.State.ToString()
    if ($st -eq 'Running') { return }
    if ($script:Busy) { Write-Term "?DEVICE NOT PRESENT  ERROR`n"; return }
    if ($Line.Trim() -ne '' -and $st -ne 'Input') {
        [void]$script:History.Add($Line)
        $script:HistIdx = $script:History.Count
    }
    try { Invoke-TermCommand $Line }
    catch {
        Write-Term ('?' + $_.Exception.Message.ToUpper() + "  ERROR`n")
        Write-Ready
    }
}

$termIn.Add_KeyDown({
    param($s, $e)
    $k = $e.KeyCode
    if ($k -eq 'Return') {
        $e.SuppressKeyPress = $true
        $line = $termIn.Text
        $termIn.Clear()
        Submit-Term $line
    }
    elseif ($k -eq 'Up') {
        $e.SuppressKeyPress = $true
        if ($script:HistIdx -gt 0) { $script:HistIdx--; $termIn.Text = [string]$script:History[$script:HistIdx]; $termIn.SelectionStart = $termIn.TextLength }
    }
    elseif ($k -eq 'Down') {
        $e.SuppressKeyPress = $true
        if ($script:HistIdx -lt $script:History.Count - 1) { $script:HistIdx++; $termIn.Text = [string]$script:History[$script:HistIdx] }
        else { $script:HistIdx = $script:History.Count; $termIn.Clear() }
    }
    elseif ($k -eq 'Escape') {
        $e.SuppressKeyPress = $true
        if ($script:Busy -and $script:ActiveSlicer) { $script:ActiveSlicer.Cancel = $true; return }
        $st = $basic.State.ToString()
        if ($st -eq 'Running' -or $st -eq 'Input') {
            $pump.Stop()
            $basic.Break()
            $basic.Col = 0
            Write-Ready
        }
    }
})
$termOut.Add_Click({ $termIn.Focus() })

# ---------------------------------------------------------------------
#  Go!
# ---------------------------------------------------------------------
$form.Add_Load({ Update-Layout })
$form.Add_Shown({
    Update-Layout
    try { $split.SplitterDistance = [int]($split.Height * 0.55) } catch { }
    Reset-Term
    $form.Activate()
})
$form.Add_FormClosing({ $pump.Stop(); if ($script:ActiveSlicer) { $script:ActiveSlicer.Cancel = $true } })

[void]$form.ShowDialog()
