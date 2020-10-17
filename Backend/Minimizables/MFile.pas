unit MFile;

uses PathUtils        in '..\..\Utils\PathUtils';

uses MinimizableCore  in '..\MinimizableCore';

type
  
  MFileLine = sealed class(MinimizableItem)
    private l: string;
    private l_n: integer;
    private fname: string;
    
    public constructor(l: string; l_n: integer; fname: string);
    begin
      self.l      := l;
      self.l_n    := l_n;
      self.fname  := fname;
    end;
    
    public procedure UnWrapTo(new_base_dir: string; is_valid_node: MinimizableNode->boolean); override :=
    raise new System.InvalidOperationException;
    
    public function ToString: string; override := $'File[{self.fname}]+Line[{self.l_n}]';
    
  end;
  
  MFileContents = sealed class(MinimizableList)
    private fname: string;
    
    public constructor(fname, base_dir: string);
    begin
      self.invulnerable := true;
      self.fname := GetRelativePath(fname, base_dir);
      
      var n := 1;
      foreach var l in ReadLines(fname) do
      begin
        self.Add( new MFileLine(l, n, self.fname) );
        n += 1;
      end;
      
    end;
    
    public procedure UnWrapTo(new_base_dir: string; is_valid_node: MinimizableNode->boolean); override;
    begin
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