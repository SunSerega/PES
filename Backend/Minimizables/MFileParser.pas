unit MFileParser;

uses PathUtils        in '..\..\Utils\PathUtils';

uses MinimizableCore  in '..\MinimizableCore';
uses MConst;

uses ParserCore       in 'Parsers\ParserCore';

type
  StringIndex = ParserCore.StringIndex;
  SIndexRange = ParserCore.SIndexRange;
  AddedText = ParserCore.AddedText;
  ParsedFile = ParserCore.ParsedFile;
  
  MFilePetrified = sealed class(MinimizableNode)
    private rel_fname, org_fname: string;
    
    public constructor(fname, base_dir, target: string);
    begin
      self.org_fname := fname;
      self.rel_fname := GetRelativePath(fname, base_dir);
      self.invulnerable := rel_fname=target;
    end;
    
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override := exit;
    public procedure AddDirectChildrenTo(l: VulnerableNodeList); override := exit;
    
    public procedure UnWrapTo(new_base_dir: string) :=
    CopyFile(
      self.org_fname,
      System.IO.Path.Combine(new_base_dir, self.rel_fname)
    );
    
  end;
  
  MFileBatch = sealed class(MinimizableContainer)
    private sub_dirs := new List<string>;
    private petrified := new MinimizableNodeList<MFilePetrified>;
    private parsed := new MinimizableNodeList<ParsedFile>;
    
    public constructor(dir, target: string);
    begin
      self.invulnerable := true;
      
      foreach var sub_dir in EnumerateAllDirectories(dir) do
        sub_dirs += GetRelativePath(sub_dir, dir);
      
      System.Threading.Tasks.Parallel.ForEach(EnumerateAllFiles(dir), fname->
//      foreach var fname in EnumerateAllFiles(dir) do
      begin
        var f := ParsedFile.ParseByExt.Get(System.IO.Path.GetExtension(fname));
        if f=nil then
          petrified += new MFilePetrified(fname, dir, target) else
        begin
          var p := f(fname, dir, target);
          {$ifdef DEBUG}
          p.AssertIntegrity;
          {$endif DEBUG}
          parsed += p;
        end;
      end);
      
    end;
    
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override;
    begin
      petrified.Cleanup(is_invalid);
         parsed.Cleanup(is_invalid);
    end;
    public procedure AddDirectChildrenTo(l: VulnerableNodeList); override;
    begin
      l += petrified;
      l += parsed;
    end;
    
    public function UnWrapTo(new_base_dir: string; need_node: MinimizableNode->boolean): integer; override;
    begin
      System.IO.Directory.CreateDirectory(new_base_dir);
      foreach var sub_dir in sub_dirs do
        System.IO.Directory.CreateDirectory( System.IO.Path.Combine(new_base_dir, sub_dir) );
      
      foreach var f in petrified.EnmrDirect do
        if (need_node=nil) or need_node(f) then
          f.UnWrapTo(new_base_dir);
      
      foreach var f in parsed.EnmrDirect do
        if (need_node=nil) or need_node(f) then
          Result += f.UnWrapTo(new_base_dir, need_node);
      
    end;
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := 0;
      
      foreach var f in parsed.EnmrDirect do
        if (need_node=nil) or need_node(f) then
          Result += f.CountLines(need_node);
      
    end;
    
    public procedure ForEachParsed(p: ParsedFile->());
    begin
      foreach var f in parsed.EnmrDirect do p(f);
    end;
    
  end;
  
end.