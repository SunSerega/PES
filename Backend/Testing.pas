unit Testing;

interface

type
  TestResult = abstract class
    private dir, target_fname, source_fname: string;
    
    public property WorkDir: string read dir;
//    public property TargetFName: string read target_fname;
    public property SourceFName: string read source_fname;
    
    public property Parent: TestResult read nil; virtual;
    
    public function GetShortDescription: string; abstract;
    public procedure ReportTo(dir: string); abstract;
    
  end;
  
  CompResult = sealed class(TestResult)
    private comp_fname: string;
    
    private otp, err: string;
    private is_module: boolean;
    
    private procedure Test;
    begin
      var psi := new System.Diagnostics.ProcessStartInfo(comp_fname, $'"{target_fname}"');
      psi.UseShellExecute := false;
      psi.CreateNoWindow := true;
      psi.RedirectStandardInput := true;
      psi.RedirectStandardOutput := true;
      psi.RedirectStandardError := true;
      psi.WorkingDirectory := dir;
      
      var p := System.Diagnostics.Process.Start(psi);
      p.StandardInput.WriteLine;
      
      var otp := new StringBuilder;
      p.OutputDataReceived += (o,e)->
      if e.Data<>nil then otp.AppendLine(e.Data);
      
      var err := new StringBuilder;
      p.ErrorDataReceived += (o,e)->
      if e.Data<>nil then err.AppendLine(e.Data);
      
      p.BeginOutputReadLine;
      p.BeginErrorReadLine;
      p.WaitForExit;
      
      self.err := err.ToString;
      if string.IsNullOrWhiteSpace(self.err) then
      begin
        self.otp := otp.ToString.Remove(#13).Trim;
        self.err := nil;
      end else
        self.err := self.err.Remove(#13).Trim;
      
      var full_fname := System.IO.Path.Combine(dir, target_fname);
      
      if not self.IsError then
      begin
        
        if System.IO.File.Exists(System.IO.Path.ChangeExtension(full_fname, '.pcu')) then
          is_module := true else
        if System.IO.File.Exists(System.IO.Path.ChangeExtension(full_fname, '.exe')) then
          is_module := false else
          raise new System.NotSupportedException($'Can''t find .pcu or .exe result file of "{full_fname}"');
        
      end;
      
//      lock output do
//      begin
//        Writeln(fname);
//        Writeln(comp_fname);
//        Writeln;
//        
//        Writeln('otp:');
//        self.otp.Println;
//        Writeln;
//        
//        Writeln('err:');
//        self.err.Println;
//        Writeln('='*30);
//        
//      end;
    end;
    
    public constructor(dir, fname, comp_fname: string);
    begin
      self.dir          := dir;
      self.target_fname := fname;
      self.source_fname := fname;
      self.comp_fname   := comp_fname;
      Test;
    end;
    public constructor(any_tr: TestResult; dir: string) :=
    while true do
    begin
      if any_tr=nil then raise new System.ArgumentException;
      if any_tr is CompResult(var ctr) then
      begin
        self.dir          := dir;
        self.target_fname := ctr.target_fname;
        self.source_fname := ctr.source_fname;
        self.comp_fname   := ctr.comp_fname;
        Test;
        exit;
      end;
      any_tr := any_tr.Parent;
    end;
    
    public function IsError := (err<>nil) or otp.ToLower.Contains('err');
    public function IsModule := self.is_module;
    public function ExecTestReasonable := not IsError and not IsModule;
    
    public function GetShortDescription: string; override;
    begin
      if err<>nil then
      begin
        var a := err.Split(#10);
        Result := a[0];
      end else
      begin
        var a := otp.Split(#10);
        Result := a[0];
        if Result.Contains('Compile errors:') and (a.Length>1) then
          Result := a[1];
      end;
    end;
    
    public procedure ReportTo(dir: string); override;
    begin
      var sw := new System.IO.StreamWriter(System.IO.Path.Combine(dir, 'CompResult.dat'), false, System.Text.Encoding.UTF8);
      loop 3 do sw.WriteLine;
      
      sw.WriteLine('# otp');
      sw.WriteLine(otp);
      sw.WriteLine;
      
      if not string.IsNullOrWhiteSpace(err) then
      begin
        sw.WriteLine('# err');
        sw.WriteLine(err);
        sw.WriteLine;
      end;
      
      loop 1 do sw.WriteLine;
      sw.Close;
    end;
    
    public static function AreSame(ctr1, ctr2: CompResult): boolean;
    begin
      Result := false;
      if ctr1.err <> ctr2.err then exit;
      if (ctr1.err=nil) and (ctr1.otp <> ctr2.otp) then exit;
      Result := true;
    end;
    
  end;
  
  [System.Serializable]
  ExceptionContainer = sealed class
    public Message: string := nil;
    public ErrType: string := nil;
    public StackTrace: string := nil;
    public AllText: string := nil;
    public constructor(e: Exception);
    begin
      self.Message := e.Message;
      self.ErrType := e.GetType.ToString;
      self.StackTrace := e.StackTrace;
      self.AllText := e.ToString;
    end;
    public constructor := exit;
  end;
  ExecResult = sealed class(TestResult)
    private const max_exec_time = 5000;
    private _parent: CompResult;
    
    private otp: string;
    private err: ExceptionContainer;
    
    private procedure Test;
    begin
      var psi := new System.Diagnostics.ProcessStartInfo(GetEXEFileName, $'"ExecTest={System.IO.Path.GetFullPath(System.IO.Path.Combine(dir,target_fname))}"');
      psi.UseShellExecute := false;
      psi.CreateNoWindow := true;
      psi.RedirectStandardOutput := true;
      psi.RedirectStandardError := true;
      psi.WorkingDirectory := dir;
      
      var p := System.Diagnostics.Process.Start(psi);
      if not p.WaitForExit(max_exec_time) then
      begin
        p.Kill;
        self.err := new ExceptionContainer;
        self.err.AllText := 'Execution took too long';
        p.WaitForExit;
        exit;
      end;
      
      self.otp := p.StandardOutput.ReadToEnd.Trim;
      var err := p.StandardError.ReadToEnd;
      
      var s := new System.Xml.Serialization.XmlSerializer(typeof(ExceptionContainer));
      try
        self.err := ExceptionContainer(s.Deserialize(new System.IO.StringReader(err)));
      except
        if not string.IsNullOrWhiteSpace(err) then
        begin
          self.err := new ExceptionContainer;
          self.err.AllText := err.Trim;
        end;
      end;
      
//      lock output do
//      begin
//        Writeln(fname);
//        Writeln;
//        
//        Writeln('otp:');
//        self.otp.Println;
//        Writeln;
//        
//        Writeln('err:');
//        (self.err?.ToString??'nil').Println;
//        Writeln('='*30);
//        
//      end;
    end;
    
    public constructor(dir, fname: string);
    begin
      self.dir          := dir;
      self.target_fname := fname;
      self.source_fname := fname;
      Test;
    end;
    public constructor(ctr: CompResult);
    begin
      if not ctr.ExecTestReasonable then raise new System.InvalidOperationException;
      self._parent  := ctr;
      self.dir      := ctr.dir;
      self.source_fname := ctr.source_fname;
      self.target_fname := System.IO.Path.ChangeExtension(source_fname, '.exe');
      Test;
    end;
    
    public property Parent: TestResult read _parent as TestResult; override;
    
    public function GetShortDescription: string; override :=
    if err=nil then otp else
    $'{err.ErrType<>nil ? err.ErrType : err.GetType.ToString}: {err.Message<>nil ? err.Message : err.AllText}';
    
    public procedure ReportTo(dir: string); override;
    begin
      if Parent<>nil then Parent.ReportTo(dir);
      var sw := new System.IO.StreamWriter(System.IO.Path.Combine(dir, 'CompResult.dat'), false, System.Text.Encoding.UTF8);
      loop 3 do sw.WriteLine;
      
      sw.WriteLine('# otp');
      sw.WriteLine(otp);
      sw.WriteLine;
      
      if err<>nil then
      begin
        sw.WriteLine('# err');
        sw.WriteLine(err.AllText.Trim(#13#10.ToArray));
        sw.WriteLine;
      end;
      
      loop 1 do sw.WriteLine;
      sw.Close;
    end;
    
    public static function AreSame(etr1, etr2: ExecResult): boolean;
    begin
      Result := false;
      if etr1.err=nil then
      begin
        if etr2.err<>nil then exit;
        if etr1.otp <> etr2.otp then exit;
      end else
      begin
        if etr2.err=nil then exit;
        if etr1.err.Message <> etr2.err.Message then exit;
      end;
      Result := true;
    end;
    
  end;
  
implementation

uses CLArgs in '..\Utils\CLArgs';
uses MessageBoxing;

procedure EmergencyThreadBody;
begin
  Sleep(ExecResult.max_exec_time);
  Console.Error.WriteLine('Emergency halt');
  Halt;
end;

begin
  try
    if GetArgs('ExecTest').SingleOrDefault is string(var fname) then
    begin
      var halt_thr := new System.Threading.Thread(EmergencyThreadBody);
      halt_thr.IsBackground := true;
      halt_thr.Start;
      
      Console.SetIn(new System.IO.StringReader(''));
      var ep := System.Reflection.Assembly.LoadFile(fname).EntryPoint;
      try
        ep.Invoke(nil, new object[0]);
      except
        on e: Exception do
        begin
          {$reference System.Xml.dll}
          var s := new System.Xml.Serialization.XmlSerializer(typeof(ExceptionContainer));
          s.Serialize(Console.Error, new ExceptionContainer(e));
        end;
      end;
      Halt;
    end;
  except
    on e: Exception do
      MessageBox.Show(e.ToString);
  end;
end.