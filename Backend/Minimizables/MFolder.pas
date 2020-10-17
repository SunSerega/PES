unit MFolder;

uses PathUtils        in '..\..\Utils\PathUtils';

uses MinimizableCore  in '..\MinimizableCore';

type
  
  MFolderFile = sealed class(MinimizableItem)
    private fname, rel_fname: string;
    
    public constructor(fname, base_dir, target: string);
    begin
      self.fname := fname;
      self.rel_fname := GetRelativePath(fname, base_dir);
      self.invulnerable := self.rel_fname=target;
    end;
    
    public procedure UnWrapTo(new_base_dir: string; is_valid_node: MinimizableNode->boolean); override :=
    System.IO.File.Copy(fname, System.IO.Path.Combine(new_base_dir, rel_fname));
    
    public function ToString: string; override := $'File[{self.rel_fname}]';
    
  end;
  
  MFolderContents = sealed class(MinimizableList)
    private rel_dir: string;
    
    public constructor(dir, base_dir, target: string);
    begin
//      self.dir := dir;
      self.rel_dir := GetRelativePath(dir, base_dir);
      
      foreach var dname in EnumerateDirectories(dir) do
        self.Add( new MFolderContents(dname, base_dir, target) );
      
      foreach var fname in EnumerateFiles(dir) do
        self.Add( new MFolderFile(fname, base_dir, target) );
      
    end;
    public constructor(dir, target: string) := Create(dir, dir, target);
    
    public procedure UnWrapTo(new_base_dir: string; is_valid_node: MinimizableNode->boolean); override;
    begin
      System.IO.Directory.CreateDirectory( System.IO.Path.Combine(new_base_dir, rel_dir) );
      inherited;
    end;
    
    public function ToString: string; override := $'Dir[{self.rel_dir}]';
    
  end;
  
end.