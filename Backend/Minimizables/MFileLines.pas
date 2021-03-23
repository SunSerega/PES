unit MFileLines;

uses PathUtils        in '..\..\Utils\PathUtils';

uses MinimizableCore  in '..\MinimizableCore';
uses MConst;

type
  
  {$region Line}
  
  MFileLine = sealed class(MinimizableNode)
    private l: string;
    private l_n: integer;
    private short_fname: string;
    
    public constructor(l: string; l_n: integer; short_fname: string);
    begin
      self.l            := l;
      self.l_n          := l_n;
      self.short_fname  := short_fname;
    end;
    
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override := exit;
    public procedure AddDirectChildrenTo(l: List<MinimizableNode>); override := exit;
    
    public procedure UnWrapTo(sw: System.IO.StreamWriter) := sw.Write(l);
    
    public function ToString: string; override := $'({self.short_fname})+Line[{self.l_n}]';
    
  end;
  
  {$endregion Line}
  
  {$region File}
  
  MFileBase = partial abstract class(MinimizableNode)
    protected rel_fname: string;
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; abstract;
    public procedure UnWrapTo(new_base_dir: string; need_node: MinimizableNode->boolean); abstract;
    
  end;
  
  MFileContents = sealed class(MFileBase)
    private lines := new MinimizableNodeList<MFileLine>;
    
    public constructor(fname, base_dir: string);
    begin
      self.rel_fname := GetRelativePath(fname, base_dir);
      
      var short_fname := System.IO.Path.GetFileName(fname);
      var n := 1;
      
      foreach var l in ReadLines(fname) do
        if not string.IsNullOrWhiteSpace(l) then //ToDo разобраться почему это всё ломает
        begin
          lines += new MFileLine(l, n, short_fname);
          n += 1;
        end;
      
    end;
    
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override := lines.Cleanup(is_invalid);
    public procedure AddDirectChildrenTo(l: List<MinimizableNode>); override := l += lines;
    
    public procedure UnWrapTo(new_base_dir: string; need_node: MinimizableNode->boolean); override;
    begin
      var sw := new System.IO.StreamWriter(
        System.IO.Path.Combine(new_base_dir, self.rel_fname),
        false, write_enc
      );
      
      try
        var first := true;
        foreach var l in lines.EnmrDirect do
          if (need_node=nil) or need_node(l) then
          begin
            if first then
              first := false else
              sw.WriteLine;
            l.UnWrapTo(sw);
          end;
      finally
        sw.Close;
      end;
      
    end;
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; override :=
    if need_node=nil then
      lines.EnmrDirect.Count else
      lines.EnmrDirect.Cast&<MinimizableNode>.Count(need_node);
    
  end;
  
  MFilePetrified = sealed class(MFileBase)
    private org_fname: string;
    
    public constructor(fname, base_dir: string);
    begin
      self.org_fname := fname;
      self.rel_fname := GetRelativePath(fname, base_dir);
    end;
    
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override := exit;
    public procedure AddDirectChildrenTo(l: List<MinimizableNode>); override := exit;
    
    public procedure UnWrapTo(new_base_dir: string; need_node: MinimizableNode->boolean); override :=
    CopyFile(
      self.org_fname,
      System.IO.Path.Combine(new_base_dir, self.rel_fname)
    );
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; override := 0;
    
  end;
  
  MFileBase = partial abstract class(MinimizableNode)
    
    public static function MakeNew(fname, base_dir, target: string): MFileBase;
    begin
      Result := if System.IO.Path.GetExtension(fname) in MinimizableFilesExtensions then
        new MFileContents (fname, base_dir) as MFileBase else
        new MFilePetrified(fname, base_dir) as MFileBase;
      Result.invulnerable := Result.rel_fname=target;
    end;
    
  end;
  
  {$endregion File}
  
  {$region Directory}
  
  MFileBatch = sealed class(MinimizableContainer)
    private sub_dirs := new List<string>;
    private files := new MinimizableNodeList<MFileBase>;
    
    public constructor(dir, target: string);
    begin
      
      foreach var sub_dir in EnumerateAllDirectories(dir) do
        sub_dirs += GetRelativePath(sub_dir, dir);
      
      foreach var fname in EnumerateAllFiles(dir) do
        files += MFileBase.MakeNew(fname, dir, target);
      
    end;
    
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override := files.Cleanup(is_invalid);
    public procedure AddDirectChildrenTo(l: List<MinimizableNode>); override := l += files;
    
    public procedure UnWrapTo(new_base_dir: string; need_node: MinimizableNode->boolean); override;
    begin
      System.IO.Directory.CreateDirectory(new_base_dir);
      foreach var sub_dir in sub_dirs do
        System.IO.Directory.CreateDirectory( System.IO.Path.Combine(new_base_dir, sub_dir) );
      
      foreach var f in files.EnmrDirect do
        if (need_node=nil) or need_node(f) then
          f.UnWrapTo(new_base_dir, need_node);
      
    end;
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := 0;
      
      foreach var f in files.EnmrDirect do
        if (need_node=nil) or need_node(f) then
          Result += f.CountLines(need_node);
      
    end;
    
  end;
  
  {$endregion Directory}
  
end.