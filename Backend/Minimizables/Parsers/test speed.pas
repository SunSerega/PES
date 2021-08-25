## uses ParserCore;//, ParserPas;

try
  
//  var t := new TextSection(' aba abababc ');
//  
//  t.Trim(' ').IndexOf('d').Println;
  
  var fnames := new List<string>;
//  fnames += 'ParserPas.pas';
//  fnames += 'C:\0Prog\PES\Bucket\OpenCL.pas';
//  fnames += 'C:\0Prog\PES\Bucket\OpenCLABC.pas';
//  fnames += 'C:\0Prog\PES\Bucket\Internal\OpenCLABCBase.pas';
//  fnames += 'C:\0Prog\PES\Bucket\MatrMlt.pas';
//  fnames += 'C:\0Prog\POCGL\Modules.Packed\OpenGL.pas';
  fnames.AddRange(EnumerateAllFiles('C:\0Prog\PES', '*.pas'));
//  fnames.AddRange(EnumerateAllFiles('C:\0Prog\PES\Bucket', '*.pas'));
  
  System.IO.Directory.CreateDirectory('temp');
  foreach var fname in fnames.Select(System.IO.Path.GetFullPath) do loop 2 do
  begin
    fname.Println;
    
    var sw := Stopwatch.StartNew;
    var f: ParsedFile := ParsedFile.ParseByExt['.pas'](fname, System.IO.Path.GetDirectoryName(fname), nil);
    sw.Stop;
    $' Parse: {sw.Elapsed}'.Println;
    
    sw.Restart;
    f.AssertIntegrity;
    sw.Stop;
    $'  Test: {sw.Elapsed}'.Println;
    
    sw.Restart;
    f.UnWrapTo('temp', nil);
    sw.Stop;
    $'UnWrap: {sw.Elapsed}'.Println;
    
  end;
  Writeln('='*30);
  
except
  on e: Exception do
    Writeln(e);
end;
System.IO.Directory.Delete('temp', true);
try
  Console.BufferWidth := Console.BufferWidth;
  Readln;
except
end;