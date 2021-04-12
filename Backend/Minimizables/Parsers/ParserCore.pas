unit ParserCore;

interface

uses PathUtils        in '..\..\..\Utils\PathUtils';

uses MinimizableCore  in '..\..\MinimizableCore';

type
  ParsedFile = abstract class(MinimizableContainer)
    protected rel_fname: string;
    
    public static ParseByExt := new Dictionary<string, function(fname, base_dir, target:string):ParsedFile>;
    
    public constructor(fname, base_dir, target: string);
    begin
      self.rel_fname := GetRelativePath(fname, base_dir);
      self.invulnerable := rel_fname=target;
    end;
    ///--
    public constructor := raise new System.InvalidOperationException;
    
    public function ToString: string; override :=
    $'File[{rel_fname}]';
    
//    public procedure UnWrapTo(new_base_dir: string; need_node: MinimizableNode->boolean); abstract;
//    public function CountLines(need_node: MinimizableNode->boolean): integer; abstract;
    
  end;
  
  ParsedFileItem = abstract class(MinimizableNode)
    protected f: ParsedFile;
    
    public constructor(f: ParsedFile) := self.f := f;
    ///--
    public constructor := raise new System.InvalidOperationException;
    
    public procedure UnWrapTo(sw: System.IO.StreamWriter; need_node: MinimizableNode->boolean); abstract;
    public function CountLines(need_node: MinimizableNode->boolean): integer; abstract;
    
  end;
  
implementation

uses ParserPas;

end.