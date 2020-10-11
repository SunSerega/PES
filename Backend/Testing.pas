unit Testing;

type
  TestResult = abstract class
    
    public function GetShortDescription: string; abstract;
    
  end;
  
  CompResult = sealed class(TestResult)
    private dir, fname, comp_fname: string;
    
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
    
    public function IsError := (err<>nil) or otp.ToLower.Contains('err');
    public function IsModule := self.is_module;
    
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
    
  end;
  
  CrossDomainExceptionContainer = sealed class(System.MarshalByRefObject)
    public e: Exception;
    public constructor(e: Exception) := self.e := e;
  end;
  ExecResult = sealed class(TestResult)
    private dir, fname: string;
    
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
      if ctr.IsError then raise new System.InvalidOperationException;
      self.dir    := ctr.dir;
      self.fname  := ctr.fname;
      Test;
    end;
    
    public function GetShortDescription: string; override;
    begin
      Result := err<>nil ? $'{err.GetType}: {err.Message}' : otp;
    end;
    
  end;
  
end.