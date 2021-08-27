unit Testing;
{$zerobasedstrings}

interface

uses SettingData;

type
  TestResult = abstract class
    private dir, target_fname, source_fname: string;
    
    public property WorkDir: string read dir;
//    public property TargetFName: string read target_fname;
    public property SourceFName: string read source_fname;
    
    public property Parent: TestResult read nil; virtual;
    
    public function GetShortDescription: string; abstract;
    
  end;
  
  CompOtp = sealed class
    public org_text: string;
    
    public location: (integer, integer) := nil;
    public fname := default(string);
    public message := default(string);
    
    public constructor(text: string);
    begin
      self.org_text := text;
      var lines := text.Split(|#10|, 2);
      if (lines.Length=1) or not lines[0].Contains('Compile errors:') then exit;
      text := lines[1];
      
      if text.StartsWith('[') then
      begin
        text := text.Substring(1);
        var ind := text.IndexOf(']', 1);
        var location_strs := text.Remove(ind).Split(',');
        var a := location_strs.ConvertAll(s->s.ToInteger);
        if a.Length<>2 then raise new System.InvalidOperationException;
        location := (a[0], a[1]);
        text := text.Substring(ind+1).TrimStart;
      end;
      var ind := text.IndexOf(':');
      if ind<>-1 then
      begin
        fname := text.Remove(ind);
        text := text.SubString(ind+1).TrimStart;
      end;
      message := text;
      
//      lock output do
//      begin
//        Writeln(org_text);
//        Writeln(location);
//        Writeln(fname);
//        Writeln(message);
//        Writeln('='*30);
//      end;
      
    end;
    
  end;
  CompResult = sealed class(TestResult)
    private comp_fname: string;
    
    private otp: CompOtp;
    private inner_err: string;
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
      
      var err_text := err.ToString;
      if string.IsNullOrWhiteSpace(err_text) then
      begin
        self.otp := new CompOtp(otp.ToString.Remove(#13).Trim);
        self.inner_err := nil;
      end else
        self.inner_err := err_text.Remove(#13).Trim;
      
      var full_fname := System.IO.Path.Combine(dir, target_fname);
      
      if not self.IsError then
      begin
        
        if System.IO.File.Exists(System.IO.Path.ChangeExtension(full_fname, '.pcu')) then
          is_module := true else
        if System.IO.File.Exists(System.IO.Path.ChangeExtension(full_fname, '.exe')) then
          is_module := false else
        if ReadLines(full_fname).Any(l->l.Contains('{'+'$savepcu false}')) then
          is_module := true else
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
      if any_tr is CompResult(var ctr) then
      begin
        self.dir          := dir;
        self.target_fname := ctr.target_fname;
        self.source_fname := ctr.source_fname;
        self.comp_fname   := ctr.comp_fname;
        Test;
        exit;
      end;
      if any_tr=nil then raise new System.ArgumentException;
      any_tr := any_tr.Parent;
    end;
    
    public function IsError := (inner_err<>nil) or otp.org_text.ToLower.Contains('err');
    public function IsModule := self.is_module;
    public function ExecTestReasonable := not IsError and not IsModule;
    
    public function GetShortDescription: string; override;
    begin
      if inner_err<>nil then
      begin
        var a := inner_err.Split(#10);
        Result := a[0];
      end else
      begin
        Result := otp.message ?? otp.org_text;
      end;
    end;
    
    public static function AreSame(ctr1, ctr2: CompResult): boolean;
    begin
      Result := false;
      if (ctr1.inner_err=nil) <> (ctr2.inner_err=nil) then exit;
      if ctr1.inner_err=nil then
      begin
        if (ctr1.otp.message=nil) <> (ctr2.otp.message=nil) then exit;
        if (ctr1.otp.message??ctr1.otp.org_text) <> (ctr2.otp.message??ctr2.otp.org_text) then exit;
      end else
      begin
        if ctr1.inner_err <> ctr2.inner_err then exit;
      end;
      Result := true;
    end;
    public static function Compare(ctr1, ctr2: CompResult): integer;
    begin
      Result := 0;
      
      Result += integer(ctr1.inner_err<>nil);
      Result -= integer(ctr2.inner_err<>nil);
      if Result<>0 then exit;
      if ctr1.inner_err<>nil then
      begin
        Result := string.Compare(ctr1.inner_err, ctr2.inner_err);
        exit;
      end;
      
      Result += integer(ctr1.otp.message=nil);
      Result -= integer(ctr2.otp.message=nil);
      if Result<>0 then exit;
      if ctr1.otp.message=nil then
      begin
        Result := string.Compare(ctr1.otp.org_text, ctr2.otp.org_text);
      end else
      begin
        Result := string.Compare(ctr1.otp.message, ctr2.otp.message);
      end;
      
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
    private _parent: CompResult;
    
    private otp: string;
    private err: ExceptionContainer;
    
    private procedure Test;
    begin
      var MaxExecTime := Settings.Current.MaxExecTime;
      var full_target_fname := System.IO.Path.GetFullPath(System.IO.Path.Combine(dir,target_fname));
      
      var psi := new System.Diagnostics.ProcessStartInfo(GetEXEFileName, $'"ExecTest={full_target_fname}" "MaxExecTime={MaxExecTime}"');
      psi.UseShellExecute := false;
      psi.CreateNoWindow := true;
      psi.RedirectStandardOutput := true;
      psi.RedirectStandardError := true;
      psi.WorkingDirectory := System.IO.Path.GetDirectoryName(full_target_fname);
      
      var p := System.Diagnostics.Process.Start(psi);
      if not p.WaitForExit(MaxExecTime) then
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
      
      // p.WaitForExit; //ToDo Всё равно .exe иногда не освобождает...
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
    public static function Compare(ctr1, ctr2: ExecResult): integer;
    begin
      
    end;
    
  end;
  
implementation

uses CLArgs in '..\Utils\CLArgs';
uses MessageBoxing;

procedure EmergencyThreadBody :=
try
  Sleep(GetArgs('MaxExecTime').Single.ToInteger);
  Console.Error.WriteLine('Emergency halt');
  Halt;
except
  on e: Exception do
    Console.Error.WriteLine(e);
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