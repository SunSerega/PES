uses PES_PackUtils  in '..\PES_PackUtils';
uses Fixers         in '..\Utils\Fixers';

function MakeSW(fname: string): System.IO.StreamWriter;
begin
  Result := new System.IO.StreamWriter(GetFullPathRTE(fname), false, enc);
  loop 3 do Result.WriteLine;
end;

const
  RawFolder = 'Settings Raw';

begin
  try
    var used      := MakeSW('Settings.Used-Modules.CodeGenRes');
    var core      := MakeSW('Settings.Core.CodeGenRes');
    var load_body := MakeSW('Settings.Load-Body.CodeGenRes');
    var save_body := MakeSW('Settings.Save-Body.CodeGenRes');
    
    var prev_used := new HashSet<string>;
    
    foreach var fname in EnumerateAllFiles(GetFullPathRTE(RawFolder), '*.dat') do
    begin
      var sn := fname.Remove(0, fname.LastIndexOf(RawFolder) + RawFolder.Length+1);
      sn := System.IO.Path.ChangeExtension(sn, nil);
      
      var tn: string := nil;
      var set_default_code: array of string := nil;
      var load_code:        array of string := nil;
      var save_code:        array of string := nil;
      
      foreach var t in FixerUtils.ReadBlocks(fname, false) do
      case t[0] of
        
        'UsedModules':
        foreach var l in t[1] do
          if prev_used.Add(l) then
            used.WriteLine($'uses {System.IO.Path.GetFileName(l)} in ''Settings Code\{l}'';');
        
        'Type':         tn                := t[1].Single;
        'InitDefault':  set_default_code  := t[1];
        'Load':         load_code         := t[1];
        'Save':         save_code         := t[1];
        
        else raise new System.InvalidOperationException($'{fname}: {t[0]}');
      end;
      
      if tn               = nil then raise new System.ArgumentException($'{fname}: tn');
      if set_default_code = nil then raise new System.ArgumentException($'{fname}: set_default_code');
      if load_code        = nil then raise new System.ArgumentException($'{fname}: load_code');
      if save_code        = nil then raise new System.ArgumentException($'{fname}: save_code');
      
      core.WriteLine($'private _{sn}: {tn};');
      core.WriteLine($'private {sn}_need_init := true;');
      core.WriteLine($'private procedure Load{sn}(lns: array of string);');
      core.WriteLine($'begin');
      core.WriteLine($'  if lns=nil then exit;');
      core.WriteLine($'  var value: {tn};');
      foreach var l in load_code do
      core.WriteLine($'  {l}');
      core.WriteLine($'  _{sn} := value;');
      core.WriteLine($'  {sn}_need_init := false;');
      core.WriteLine($'end;');
      core.WriteLine($'private procedure Save{sn}(sw: System.IO.StreamWriter);');
      core.WriteLine($'begin');
      core.WriteLine($'  sw.WriteLine(''# {sn}'');');
      core.WriteLine($'  var value := _{sn};');
      foreach var l in save_code do
      core.WriteLine($'  {l}');
      core.WriteLine($'end;');
      core.WriteLine($'private function Get{sn}: {tn};');
      core.WriteLine($'begin');
      core.WriteLine($'  if {sn}_need_init then');
      core.WriteLine($'  begin');
      foreach var l in set_default_code do
      core.WriteLine($'    {l}');
      core.WriteLine($'    _{sn} := Result;');
      core.WriteLine($'    {sn}_need_init := false;');
      core.WriteLine($'    FastSave(Save{sn});');
      core.WriteLine($'  end else');
      core.WriteLine($'    Result := _{sn};');
      core.WriteLine($'end;');
      core.WriteLine($'public property {sn}: {tn} read Get{sn} write');
      core.WriteLine($'begin');
      core.WriteLine($'  _{sn} := value;');
      core.WriteLine($'  {sn}_need_init := false;');
      core.WriteLine($'  FastSave(Save{sn});');
      core.WriteLine($'end;');
      core.WriteLine;
      
      load_body.WriteLine($'Load{sn}(d.Get(''{sn}''));');
      save_body.WriteLine($'if not {sn}_need_init then Save{sn}(sw);');
      
    end;
    
    loop 2 do used.WriteLine;
    loop 1 do core.WriteLine;
    loop 2 do load_body.WriteLine;
    loop 2 do save_body.WriteLine;
    
    used.Close;
    core.Close;
    load_body.Close;
    save_body.Close;
  except
    on e: Exception do ErrOtp(e);
  end;
end.