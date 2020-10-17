unit Testing;

type
  TestResult = abstract class
    private dir, fname: string;
    
    public property WorkDir: string read dir;
    public property TargetFName: string read fname;
    
    public property Parent: TestResult read nil; virtual;
    
    public function GetShortDescription: string; abstract;
    
  end;
  
  CompResult = sealed class(TestResult)
    private comp_fname: string;
    
    private otp, err: string;
    private is_module: boolean;
    
    private procedure Test;
    begin
      var psi := new System.Diagnostics.ProcessStartInfo(comp_fname, $'"{fname}"');
      psi.UseShellExecute := false;
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
      
      var full_fname := System.IO.Path.Combine(dir, fname);
      
      if System.IO.File.Exists(System.IO.Path.ChangeExtension(full_fname, '.pcu')) then
        is_module := true else
      if System.IO.File.Exists(System.IO.Path.ChangeExtension(full_fname, '.exe')) then
        is_module := false else
        raise new System.NotSupportedException($'Can''t find .pcu or .exe result file of "{full_fname}"');
      
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
      self.dir        := dir;
      self.fname      := fname;
      self.comp_fname := comp_fname;
      Test;
    end;
    public constructor(any_tr: TestResult; dir: string) :=
    while true do
    begin
      if any_tr=nil then raise new System.ArgumentException;
      if any_tr is CompResult(var ctr) then
      begin
        self.dir        := dir;
        self.fname      := ctr.fname;
        self.comp_fname := ctr.comp_fname;
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
    
    public static function AreSame(ctr1, ctr2: CompResult): boolean;
    begin
      Result := false;
      if ctr1.err <> ctr2.err then exit;
      if (ctr1.err=nil) and (ctr1.otp <> ctr2.otp) then exit;
      Result := true;
    end;
    
  end;
  
  CrossDomainExceptionContainer = sealed class(System.MarshalByRefObject)
    public e: Exception;
    public constructor(e: Exception) := self.e := e;
  end;
  ExecResult = sealed class(TestResult)
    private _parent: CompResult;
    
    private otp: string;
    private err: Exception;
    
    private static procedure TestBody :=
    try
      var ad := System.AppDomain.CurrentDomain;
      var ec := ad.GetData('ec') as CrossDomainExceptionContainer;
      var fname := ad.GetData('fname') as string;
      
      var ep := System.Reflection.Assembly.LoadFile(fname).EntryPoint;
      var otp := new System.IO.StringWriter;
      Console.SetOut(otp);
      
      try
        ep.Invoke(nil, new object[0]);
      except
        on e: Exception do
          ec.e := e;
      end;
      
      ad.SetData('otp', otp.ToString.Remove(#13).Trim);
    except
      on e: Exception do
        System.AppDomain.CurrentDomain.SetData('internal err', new CrossDomainExceptionContainer(e));
    end;
    private procedure Test;
    begin
      var ad := System.AppDomain.CreateDomain($'Execution of "{fname}"');
      
      var ec := new CrossDomainExceptionContainer;
      ad.SetData('ec', ec);
      ad.SetData('fname', System.IO.Path.ChangeExtension(System.IO.Path.Combine(dir, fname), '.exe'));
      
      ad.DoCallBack(TestBody);
      
      if ad.GetData('internal err') is CrossDomainExceptionContainer(var internal_err) then
        System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(internal_err.e).Throw;
      
      self.err := ec.e;
      self.otp := ad.GetData('otp') as string;
      
      System.AppDomain.Unload(ad);
      
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
      self.dir    := dir;
      self.fname  := fname;
      Test;
    end;
    public constructor(ctr: CompResult);
    begin
      if not ctr.ExecTestReasonable then raise new System.InvalidOperationException;
      self._parent  := ctr;
      self.dir      := ctr.dir;
      self.fname    := ctr.fname;
      Test;
    end;
    
    public property Parent: TestResult read _parent as TestResult; override;
    
    public function GetShortDescription: string; override;
    begin
      Result := err<>nil ? $'{err.GetType}: {err.Message}' : otp;
    end;
    
    public static function AreSame(etr1, etr2: ExecResult): boolean;
    begin
      Result := false;
      if etr1.err.GetType <> etr2.err.GetType then exit;
      if etr1.err.Message <> etr2.err.Message then exit;
      if (etr1.err=nil) and (etr1.otp <> etr2.otp) then exit;
      Result := true;
    end;
    
  end;
  
end.