unit MFolder;

uses PathUtils        in '..\..\Utils\PathUtils';

uses MinimizableCore  in '..\MinimizableCore';
uses MConst;

type
  
  MFolderFile = sealed class(MinimizableNode)
    private fname, rel_fname, short_name: string;
    
    public constructor(fname, base_dir, target: string);
    begin
      self.fname := fname;
      self.rel_fname := GetRelativePath(fname, base_dir);
      self.short_name := System.IO.Path.GetFileName(fname);
      self.invulnerable := self.rel_fname=target;
    end;
    
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override := exit;
    public procedure AddDirectChildrenTo(l: List<MinimizableNode>); override := exit;
    
    public procedure UnWrapTo(new_base_dir: string) :=
    System.IO.File.Copy(fname, System.IO.Path.Combine(new_base_dir, rel_fname));
    
    public function CountLines :=
    if System.IO.Path.GetExtension(fname) in MinimizableFilesExtensions then
      ReadLines(fname).Count else 0;
    
    public function ToString: string; override := $'File[{self.short_name}]';
    
  end;
  
  MFolderContents = sealed class(MinimizableContainer)
    private rel_dir: string;
    private   files := new MinimizableNodeList<MFolderFile>;
    private folders := new MinimizableNodeList<MFolderContents>;
    
    public constructor(dir, base_dir, target: string);
    begin
//      self.dir := dir;
      self.rel_dir := GetRelativePath(dir, base_dir);
      
      foreach var fname in EnumerateFiles(dir) do
        files += new MFolderFile(fname, base_dir, target);
      
      foreach var fname in EnumerateDirectories(dir) do
        folders += new MFolderContents(fname, base_dir, target);
      
    end;
    public constructor(dir, target: string) := Create(dir, dir, target);
    
    public property IsInvulnerable: boolean read self.invulnerable or files.IsInvulnerable or folders.IsInvulnerable; override;
    
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override;
    begin
        files.Cleanup(is_invalid);
      folders.Cleanup(is_invalid);
    end;
    
    public procedure AddDirectChildrenTo(l: List<MinimizableNode>); override;
    begin
      l += files;
      l += folders;
    end;
    
    public procedure UnWrapTo(new_base_dir: string; need_node: MinimizableNode->boolean); override;
    begin
      var created_dir := System.IO.Path.Combine(new_base_dir, rel_dir);
      System.IO.Directory.CreateDirectory( created_dir );
      
      foreach var f in files.EnmrDirect do
        if (need_node=nil) or need_node(f) then
          f.UnWrapTo(new_base_dir);
      
      foreach var f in folders.EnmrDirect do
        if (need_node=nil) or need_node(f) then
          f.UnWrapTo(new_base_dir, need_node);
      
    end;
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := 0;
      
      foreach var f in files.EnmrDirect do
        if (need_node=nil) or need_node(f) then
          Result += f.CountLines;
      
      foreach var f in folders.EnmrDirect do
        if (need_node=nil) or need_node(f) then
          Result += f.CountLines(need_node);
      
    end;
    
    public function ToString: string; override := $'Dir[{self.rel_dir}]';
    
  end;
  
end.