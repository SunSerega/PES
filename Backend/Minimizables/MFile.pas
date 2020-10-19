unit MFile;

uses PathUtils        in '..\..\Utils\PathUtils';

uses MinimizableCore  in '..\MinimizableCore';

type
  
  MFileLine = sealed class(MinimizableItem)
    private l: string;
    private l_n: integer;
    private short_fname: string;
    
    public constructor(l: string; l_n: integer; short_fname: string);
    begin
      self.l            := l;
      self.l_n          := l_n;
      self.short_fname  := short_fname;
    end;
    
    public procedure UnWrapTo(new_base_dir: string; is_valid_node: MinimizableNode->boolean); override :=
    raise new System.InvalidOperationException;
    
    public function ToString: string; override := $'({self.short_fname})+Line[{self.l_n}]';
    
  end;
  
  MFileContents = sealed class(MinimizableList)
    private fname: string;
    private org_fname: string := nil;
    
    public constructor(fname, base_dir: string);
    begin
      self.invulnerable := true;
      self.fname := GetRelativePath(fname, base_dir);
      var short_fname := System.IO.Path.GetFileName(fname);
      
      case System.IO.Path.GetExtension(fname) of
        
        '.pas':
        begin
          var n := 1;
          foreach var l in ReadLines(fname) do
          begin
            self.Add( new MFileLine(l, n, short_fname) );
            n += 1;
          end;
        end;
        
        else self.org_fname := fname;
      end;
      
    end;
    
    public procedure UnWrapTo(new_base_dir: string; is_valid_node: MinimizableNode->boolean); override;
    begin
      if self.org_fname<>nil then
      begin
        System.IO.File.Copy(
          self.org_fname,
          System.IO.Path.Combine(new_base_dir, self.fname)
        );
        exit;
      end;
      
      var fs := new System.IO.StreamWriter(
        System.IO.Path.Combine(new_base_dir, fname),
        false, System.Text.Encoding.UTF8
      );
      
      foreach var l in items.Cast&<MFileLine> do
        if is_valid_node(l) then
          fs.WriteLine(l.l);
      
      fs.Close;
    end;
    
  end;
  
  MFileBatch = sealed class(MinimizableList)
    private sub_dirs := new List<string>;
    
    public constructor(dir: string);
    begin
      self.invulnerable := true;
      
      foreach var sub_dir in EnumerateAllDirectories(dir) do
        sub_dirs += GetRelativePath(sub_dir, dir);
      
      foreach var fname in EnumerateAllFiles(dir) do
        self.Add( new MFileContents(fname, dir) );
      
    end;
    
    public procedure UnWrapTo(new_base_dir: string; is_valid_node: MinimizableNode->boolean); override;
    begin
      System.IO.Directory.CreateDirectory(new_base_dir);
      foreach var sub_dir in sub_dirs do
        System.IO.Directory.CreateDirectory( System.IO.Path.Combine(new_base_dir, sub_dir) );
      inherited;
    end;
    
  end;
  
end.