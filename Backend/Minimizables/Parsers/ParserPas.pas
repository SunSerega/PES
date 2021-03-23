unit ParserPas;
{$string_nullbased+}

interface

uses MConst           in '..\MConst';

uses MinimizableCore  in '..\..\MinimizableCore';
uses ParserCore;

type
  
  ParsedPasFile = partial sealed class(ParsedFile)
    
    public constructor(fname, base_dir, target: string);
    
//    public property IsInvulnerable: boolean read boolean(invulnerable); override;
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override;
    public procedure AddDirectChildrenTo(l: List<MinimizableNode>); override;
    
    public procedure UnWrapTo(new_base_dir: string; need_node: MinimizableNode->boolean); override;
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    
  end;
  
implementation

type
  
  {$region Utils}
  
  TextSection = record
    text: string;
    i1, i2: integer; // [i1,i2)
    
    constructor(text: string; i1, i2: integer);
    begin
      self.text := text;
      self.i1 := i1;
      self.i2 := i2;
    end;
    constructor(text: string) := Create(text, 0, text.Length);
    
    function CountOf(ch: char): integer;
    begin
      for var i := i1 to i2-1 do
        Result += integer( text[i]=ch );
    end;
    
    public function ToString: string; override :=
    text.Substring(i1,i2-i1);
    
  end;
  
  {$endregion Utils}
  
  {$region Misc}
  
  MiscTextBlock = sealed class(ParsedFileItem)
    private text: TextSection;
    private rel_fname: string;
    
    public constructor(text: TextSection; rel_fname: string);
    begin
      self.text := text;
      self.rel_fname := rel_fname;
    end;
    
//    public property IsInvulnerable: boolean read boolean(invulnerable); override;
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override := exit;
    public procedure AddDirectChildrenTo(l: List<MinimizableNode>); override := exit;
    
    public procedure UnWrapTo(sw: System.IO.StreamWriter; need_node: MinimizableNode->boolean); override :=
    sw.Write( text.ToString );
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; override :=
    text.CountOf(#10);
    
    public function ToString: string; override := $'({self.rel_fname})+Text[{text}]';
    
  end;
  
  {$endregion Misc}
  
  {$region Operator}
  
  {$endregion Operator}
  
  {$region Method}
  
  {$endregion Method}
  
  {$region Type}
  
  {$endregion Type}
  
{$region ParsedPasFile}

type
  ParsedPasFile = partial sealed class(ParsedFile)
    private body: MiscTextBlock;
    
  end;
  
constructor ParsedPasFile.Create(fname, base_dir, target: string);
begin
  inherited Create(fname, base_dir, target);
  var ToDo := 0;
  
  var text := new TextSection( ReadAllText(fname) );
  body := new MiscTextBlock(text, self.rel_fname);
end;

procedure ParsedPasFile.CleanupBody(is_invalid: MinimizableNode->boolean);
begin
  var ToDo := 0;
end;

procedure ParsedPasFile.AddDirectChildrenTo(l: List<MinimizableNode>);
begin
  var ToDo := 0;
  l += body;
end;

procedure ParsedPasFile.UnWrapTo(new_base_dir: string; need_node: MinimizableNode->boolean);
begin
  var sw := new System.IO.StreamWriter(
    System.IO.Path.Combine(new_base_dir, self.rel_fname),
    false, write_enc
  );
  
  try
    var ToDo := 0;
    body.UnWrapTo(sw, need_node);
  finally
    sw.Close;
  end;
  
end;

function ParsedPasFile.CountLines(need_node: MinimizableNode->boolean): integer;
begin
  Result := 1;
  
  var ToDo := 0;
  Result += body.CountLines(need_node);
  
end;

{$endregion ParsedPasFile}

function ParseFile(fname, base_dir, target: string) := new ParsedPasFile(fname, base_dir, target);

begin
  ParsedFile.ParseByExt.Add('.pas', ParseFile);
end.