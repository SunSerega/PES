unit SettingData;

uses Fixers     in '..\Utils\Fixers';
uses PathUtils  in '..\Utils\PathUtils';

{$include Settings.Used-Modules.CodeGenRes}

uses MessageBoxing;

type
  Settings = sealed class
    private fname: string;
    
    private static enc := new System.Text.UTF8Encoding(true);
    
    private fast_saves_count := 0;
    private const max_fast_saves = 1024;
    private procedure FastSave(save_proc: System.IO.StreamWriter->()) := lock self do
    if fast_saves_count = max_fast_saves then
    begin
      Save;
      fast_saves_count := 0;
    end else
    begin
      var bu_fname := fname+'.backup';
      System.IO.File.Copy(fname, bu_fname, true);
      var sw := new System.IO.StreamWriter(fname, true, enc);
      
      if fast_saves_count=0 then sw.WriteLine;
      save_proc(sw);
      fast_saves_count += 1;
      
      sw.Close;
      System.IO.File.Delete(bu_fname);
    end;
    
    {$include Settings.Core.CodeGenRes}
    
    private static _curr: Settings;
    private static need_curr_init := true;
    private static function GetCurrent: Settings;
    begin
      if need_curr_init then
      begin
        _curr := new Settings;
        need_curr_init := false;
      end;
      Result := _curr;
    end;
    public static property Current: Settings read GetCurrent write
    begin
      _curr := value;
      need_curr_init := false;
    end;
    
    public constructor(fname: string);
    begin
      self.fname := fname;
      
      var bu_fname := fname+'.backup';
      if FileExists(bu_fname) then
      case MessageBox.Show($'Load backup from [{GetFullPath(bu_fname)}]?'+#10'Press cancel to halt.', 'Settings backup found', MessageBoxButton.YesNoCancel) of
        
        MessageBoxResult.Yes: fname := bu_fname;
        
        MessageBoxResult.No: ;
        
        MessageBoxResult.Cancel: Halt;
        
      end;
      
      if FileExists(fname) then
      begin
        
        var d := new Dictionary<string, array of string>;
        foreach var t in FixerUtils.ReadBlocks(fname, false) do
          d[t[0]] := t[1];
        
        {$include Settings.Load-Body.CodeGenRes}
      end;
      
      Save(self.fname);
    end;
    public constructor := Create(GetFullPathRTA('Settings.dat'));
    
    public procedure Save(fname: string);
    begin
      var bu_fname := (self.fname = fname) and FileExists(fname) ? fname+'.backup' : nil;
      if bu_fname<>nil then
      begin
        System.IO.File.Delete(bu_fname);
        System.IO.File.Move(fname, bu_fname);
      end;
      
      var sw := new System.IO.StreamWriter(fname, false, enc);
      loop 3 do sw.WriteLine;
      {$include Settings.Save-Body.CodeGenRes}
      loop 1 do sw.WriteLine;
      sw.Close;
      
      if bu_fname<>nil then
        System.IO.File.Delete(bu_fname);
    end;
    public procedure Save := Save(self.fname);
    
  end;
  
end.