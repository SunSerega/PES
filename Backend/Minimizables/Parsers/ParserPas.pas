unit ParserPas;
{$string_nullbased+}

//ToDo Пройтись по всем ToDo

//ToDo Предупреждения
//ToDo Проверка UnWrap-а при запуске с дебагом

interface

uses MConst           in '..\MConst';

uses MinimizableCore  in '..\..\MinimizableCore';
uses ParserCore;

type
  
  ParsedPasFile = partial sealed class(ParsedFile)
    
    public constructor(fname, base_dir, target: string);
    
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override;
    protected procedure AddDirectChildrenTo(l: List<MinimizableNode>); override;
    
    public procedure UnWrapTo(new_base_dir: string; need_node: MinimizableNode->boolean); override;
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
     
  end;
  
implementation

type
  
  {$region Utils}
  
  StringIndex = record
    private val: integer;
    
    private static function MakeInvalid: StringIndex;
    begin
      Result.val := -1; // Note UnsafeInc
    end;
    public static property Invalid: StringIndex read MakeInvalid;
    public property IsInvalid: boolean read val=-1;
    
    public static function operator implicit(ind: integer): StringIndex;
    begin
      if ind<0 then raise new System.IndexOutOfRangeException($'Index was {ind}');
      Result.val := ind;
    end;
    public static function operator implicit(ind: StringIndex): integer := ind.val;
    
    public static function operator=(ind1, ind2: StringIndex) := ind1.val=ind2.val;
    public static function operator=(ind1: StringIndex; ind2: integer) :=
    (ind1.val=ind2) and not ind1.IsInvalid;
    public static function operator=(ind1: integer; ind2: StringIndex) :=
    (ind1=ind2.val) and not ind2.IsInvalid;
    
    public static function operator<(ind1, ind2: StringIndex): boolean;
    begin
      if ind1.IsInvalid then raise new System.ArgumentOutOfRangeException('ind1');
      if ind2.IsInvalid then raise new System.ArgumentOutOfRangeException('ind2');
      Result := ind1.val < ind2.val;
    end;
    public static function operator>(ind1, ind2: StringIndex): boolean;
    begin
      if ind1.IsInvalid then raise new System.ArgumentOutOfRangeException('ind1');
      if ind2.IsInvalid then raise new System.ArgumentOutOfRangeException('ind2');
      Result := ind1.val > ind2.val;
    end;
    public static function operator<=(ind1, ind2: StringIndex) := not (ind1>ind2);
    public static function operator>=(ind1, ind2: StringIndex) := not (ind1<ind2);
    
    public static function operator+(ind: StringIndex; shift: integer): StringIndex;
    begin
      if ind.IsInvalid then raise new System.ArgumentOutOfRangeException;
      Result := ind.val + shift;
    end;
    public static function operator-(ind: StringIndex; shift: integer): StringIndex;
    begin
      if ind.IsInvalid then raise new System.ArgumentOutOfRangeException;
      Result := ind.val - shift;
    end;
    public function UnsafeInc: StringIndex;
    begin
      // No .IsInvalid check: Invalid+1=0
      Result.val := self.val+1;
    end;
    
    public static procedure operator+=(var ind: StringIndex; shift: integer) := ind := ind + shift;
    public static procedure operator-=(var ind: StringIndex; shift: integer) := ind := ind - shift;
    
    public static function operator-(ind1, ind2: StringIndex): integer;
    begin
      if ind1.IsInvalid then raise new System.ArgumentOutOfRangeException('ind1');
      if ind2.IsInvalid then raise new System.ArgumentOutOfRangeException('ind2');
      Result := ind1.val - ind2.val;
    end;
    
    public function ToString: string; override :=
    if self.IsInvalid then 'Invalid' else self.val.ToString;
    public function Print: StringIndex;
    begin
      self.ToString.Print;
      Result := self;
    end;
    public function Println: StringIndex;
    begin
      self.ToString.Println;
      Result := self;
    end;
    
  end;
  
  TextSection = record
    private text: string := nil;
    private i1, i2: StringIndex; // [i1,i2)
    
    public property Length: integer read i2 - i1;
    
    public static property Invalid: TextSection read default(TextSection);
    public property IsInvalid: boolean read text=nil;
    
    public constructor(text: string; i1, i2: StringIndex);
    begin
      if i1>i2 then raise new System.InvalidOperationException($'TextSection cannot have range {i1}..{i2}');
      self.text := text;
      self.i1 := i1;
      self.i2 := i2;
    end;
    public constructor(text: string) := Create(text, 0, text.Length);
    
    public procedure ValidateIndex(ind: StringIndex) :=
    if (ind >= StringIndex(Length)) then raise new System.IndexOutOfRangeException($'Index {ind} was > {Length}');
    
    private function GetItemAt(ind: StringIndex): char;
    begin
      ValidateIndex(ind);
      Result := text[self.i1+ind];
    end;
    public property Item[ind: StringIndex]: char read GetItemAt write
    begin
      ValidateIndex(ind);
      text[self.i1+ind] := value;
    end; default;
    public function Last := text[i2-1];
    
    public function WithI1(i1: StringIndex) := new TextSection(text, i1, i2);
    public function WithI2(i2: StringIndex) := new TextSection(text, i1, i2);
    
    public function TrimStart(chars: string): TextSection;
    begin
      Result := self;
      while (Result.Length<>0) and (Result[0] in chars) do
        Result.i1 += 1;
    end;
    public function TrimEnd(chars: string): TextSection;
    begin
      Result := self;
      while (Result.Length<>0) and (Result.Last in chars) do
        Result.i2 -= 1;
    end;
    public function Trim(chars: string) := self.TrimStart(chars).TrimEnd(chars);
    
    public function TrimStart(i1_shift: StringIndex) := new TextSection(self.text, self.i1+i1_shift, self.i2);
    public function TrimEnd  (i2_shift: StringIndex) := new TextSection(self.text, self.i1, self.i2-i2_shift);
    
    public function TakeFirst(len: StringIndex): TextSection;
    begin
      ValidateIndex(len);
      Result := new TextSection(self.text, self.i1, self.i1+len);
    end;
    public function TakeLast(len: StringIndex): TextSection;
    begin
      ValidateIndex(len);
      Result := new TextSection(self.text, self.i2-len, self.i2);
    end;
    
    public function TrimAfterFirst(ch: char): TextSection;
    begin
      var ind := self.IndexOf(ch);
      Result := if ind.IsInvalid then
        TextSection.Invalid else
        new TextSection(self.text, self.i1, self.i1+ind+1);
    end;
    public function TrimAfterFirst(str: string): TextSection;
    begin
      var ind := self.IndexOf(str);
      Result := if ind.IsInvalid then
        TextSection.Invalid else
        new TextSection(self.text, self.i1, self.i1+ind+str.Length);
    end;
    
    public function SubSection(ind1, ind2: StringIndex): TextSection;
    begin
      ValidateIndex(ind2-1);
      Result := new TextSection(self.text, self.i1+ind1, self.i1+ind2);
    end;
    
    public function IsWhiteSpace: boolean;
    begin
      Result := true;
      for var i: integer := i1 to i2-1 do
      begin
        Result := char.IsWhiteSpace( text[i] );
        if not Result then break;
      end;
    end;
    public function CountOf(ch: char): integer;
    begin
      for var i: integer := i1 to i2-1 do
        Result += integer( text[i].ToUpper = ch.ToUpper );
    end;
    
    public static function operator=(text1, text2: TextSection): boolean;
    begin
      Result := false;
      if text1.Length <> text2.Length then exit;
      for var i := 0 to text1.Length-1 do
        if text1[i]<>text2[i] then exit;
      Result := true;
    end;
    public static function operator=(text: TextSection; str: string): boolean;
    begin
      Result := false;
      if str=nil then raise new System.ArgumentNullException;
      if text.IsInvalid then exit;
      if text.Length<>str.Length then exit;
      for var i := 0 to str.Length-1 do
        if text[i]<>str[i] then exit;
      Result := true;
    end;
    public static function operator=(str: string; text: TextSection): boolean := text=str;
    
    public function StartsWith(str: string): boolean;
    begin
      Result := false;
      for var i := 0 to str.Length-1 do
        if str[i].ToUpper <> self[i].ToUpper then
          exit;
      Result := true;
    end;
    
    public function IndexOf(ch: char): StringIndex;
    begin
      ch := ch.ToUpper;
      for var i: integer := self.i1 to self.i2-1 do
        if text[i].ToUpper = ch then
        begin
          Result := i - integer(self.i1);
          exit;
        end;
      Result := StringIndex.Invalid;
    end;
    public function IndexOf(from: StringIndex; ch: char): StringIndex;
    begin
      Result := self.TrimStart(from).IndexOf(ch);
      if Result.IsInvalid then exit;
      Result += from;
    end;
    public function IndexOf(ch_validator: char->boolean): StringIndex;
    begin
      for var i: integer := self.i1 to self.i2-1 do
        if ch_validator(text[i]) then
        begin
          Result := i - integer(self.i1);
          exit;
        end;
      Result := StringIndex.Invalid;
    end;
    
    private static KMP_Cache := new Dictionary<string, array of StringIndex>;
    public function KMP_GetHeader(str: string): array of StringIndex;
    begin
      if KMP_Cache.TryGetValue(str, Result) then exit;
      
      Result := new StringIndex[str.Length];
      var curr_ind := StringIndex.Invalid;
      Result[0] := curr_ind;
      for var i := 1 to str.Length-1 do
      begin
        while true do
        begin
          var next_ind := curr_ind.UnsafeInc;
          if str[i] = str[next_ind] then
            curr_ind := next_ind else
          if not curr_ind.IsInvalid then
          begin
            curr_ind := Result[curr_ind];
            continue;
          end;
          break;
        end;
        Result[i] := curr_ind;
      end;
      
      KMP_Cache[str] := Result;
    end;
    
    public function IndexOf(str: string): StringIndex;
    begin
      if str.Length=0 then raise new System.ArgumentException;
      str := str.ToUpper;
      var header := KMP_GetHeader(str);
      var curr_ind := StringIndex.Invalid;
      
      for var i: integer := self.i1 to self.i2-str.Length do
        while true do
        begin
          var next_ind := curr_ind.UnsafeInc;
          if text[i].ToUpper = str[next_ind] then
          begin
            curr_ind := next_ind;
            if curr_ind = str.Length-1 then
            begin
              Result := i-integer(self.i1)-str.Length+1;
              exit;
            end;
          end else
          if not curr_ind.IsInvalid then
          begin
            curr_ind := header[curr_ind];
            continue;
          end;
          break;
        end;
      
      Result := StringIndex.Invalid;
    end;
    public function IndexOf(from: StringIndex; str: string): StringIndex;
    begin
      Result := self.TrimStart(from).IndexOf(str);
      if Result.IsInvalid then exit;
      Result += from;
    end;
    
    public function SubSectionOfFirst(params strs: array of string): TextSection;
    begin
      var min_str_len := strs.Min(str->str.Length);
      if min_str_len=0 then raise new System.ArgumentException(strs.JoinToString(#10));
      strs.Transform(str->str.ToUpper);
      var headers := strs.ConvertAll(KMP_GetHeader);
      var curr_inds := ArrFill(strs.Length, StringIndex.Invalid);
      
      for var text_i: integer := self.i1 to self.i2-min_str_len do
      begin
        var text_ch := text[text_i].ToUpper;
        for var str_i := 0 to strs.Length-1 do
        begin
          var str := strs[str_i];
          var header := headers[str_i];
          var curr_ind := curr_inds[str_i];
          
          while true do
          begin
            var next_ind := curr_ind.UnsafeInc;
            if text_ch = str[next_ind] then
            begin
              curr_ind := next_ind;
              if curr_ind = str.Length-1 then
              begin
                var ind_end := text_i+1;
                Result := new TextSection(self.text, ind_end-str.Length, ind_end);
                exit;
              end;
            end else
            if not curr_ind.IsInvalid then
            begin
              curr_ind := header[curr_ind];
              continue;
            end;
            break;
          end;
          
          curr_inds[str_i] := curr_ind;
        end;
      end;
      
      Result := TextSection.Invalid;
    end;
    
    public function ToString: string; override :=
    if self.IsInvalid then 'Invalid' else text.Substring(i1,i2-i1);
    
  end;
  
  {$endregion Utils}
  
  {$region Text}
  
  JTextBlockPart = abstract class(ParsedFileItem)
    
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override := exit;
    protected procedure AddDirectChildrenTo(l: List<MinimizableNode>); override := exit;
    
  end;
  
  MiscTextBlock = sealed class(JTextBlockPart)
    private text: TextSection;
    private text_type: string;
    
    public const  MiscText = 'MiscText';
    public const   Comment = 'Comment';
    public const Directive = 'Directive';
    
    public constructor(text: TextSection; f: ParsedPasFile; text_type: string);
    begin
      inherited Create(f);
      if text.Length=0 then raise new System.InvalidOperationException;
      self.text := text;
      self.text_type := text_type;
      
      case text_type of
         MiscText: if not text.IsWhiteSpace then ; //ToDo предупреждение
          Comment: ;
        Directive: ;
        else raise new System.InvalidOperationException(text_type);
      end;
      
    end;
    
    public static function ReadEndSpaces(var ptext: TextSection; f: ParsedPasFile): MiscTextBlock;
    begin
      var text := ptext;
      
      var ind := 0;
      var max_len := text.Length;
      while (ind<max_len) and char.IsWhiteSpace(text.TrimEnd(ind).Last) do
        ind += 1;
      if ind=0 then exit;
      
      ptext := text.TrimEnd(ind);
      Result := new MiscTextBlock(text.TakeLast(ind), f, MiscTextBlock.MiscText);
    end;
    
    public procedure UnWrapTo(sw: System.IO.StreamWriter; need_node: MinimizableNode->boolean); override := sw.Write( text.ToString );
    public function CountLines(need_node: MinimizableNode->boolean): integer; override := text.CountOf(#10);
    
    public function ToString: string; override :=
    $'{self.f}:{text_type} >>>{text}<<<';
    
  end;
  MissingTextBlock = sealed class(JTextBlockPart)
    private descr: string;
    
    public constructor(descr: string; f: ParsedPasFile);
    begin
      inherited Create(f);
      self.descr := descr;
    end;
    
    public procedure UnWrapTo(sw: System.IO.StreamWriter; need_node: MinimizableNode->boolean); override := exit;
    public function CountLines(need_node: MinimizableNode->boolean): integer; override := 0;
    
    public function ToString: string; override := $'{self.f} ~~~ Missing[{descr}]<<<';
    
  end;
  
  JTextBlock = sealed class(ParsedFileItem)
    private parts := new MinimizableNodeList<JTextBlockPart>;
    private static comment_end_dict := new Dictionary<string, string>;
    private const not_really_comment_start = '{$';
    private const literal_string_start: string = '''';
    
    static constructor;
    begin
      comment_end_dict := '{~} //~'#10' (*~*)'.ToWords
        .Select(w->w.Split(|'~'|,2))
        .ToDictionary(w->w[0], w->w[1]);
    end;
    
    public constructor(_text: TextSection; f: ParsedPasFile; stoppers: sequence of string; stopper_validator: (string, TextSection, TextSection)->TextSection; var found_stopper_kw: string; var found_stopper_section: TextSection);
    begin
      inherited Create(f);
      var expected_sub_strs := (stoppers + comment_end_dict.Keys + |literal_string_start|).ToArray;
      
      var used_head := _text;
      var read_head := _text;
      while true do
      begin
        var sub_section := read_head.SubSectionOfFirst(expected_sub_strs);
        
        // Nothing found - add rest as text and exit
        if sub_section.IsInvalid then
        begin
          if used_head.Length<>0 then
            parts.Add(new MiscTextBlock(used_head, f, MiscTextBlock.MiscText));
          found_stopper_kw := nil;
          found_stopper_section := TextSection.Invalid;
          exit;
        end;
        read_head := read_head.WithI1(sub_section.i2);
        
        var kw := sub_section.ToString.ToUpper;
        if kw = literal_string_start then
        begin
          var ls_end_ind := read_head.IndexOf(literal_string_start);
          if ls_end_ind.IsInvalid then
            {ToDo предупреждение} else
            read_head := read_head.WithI1(read_head.i1 + ls_end_ind + literal_string_start.Length);
          continue;
        end;
        
        // Expand sub_section to contain whole comment / whole code block
        // - Note: sub_string isn't updated
        var is_comment := comment_end_dict.ContainsKey(kw);
        var is_directive := false;
        if is_comment then
        begin
          sub_section := sub_section.WithI2(_text.i2).TrimAfterFirst(
            comment_end_dict[kw]
          );
          //ToDo Может стоит лучше обрабатывать, если конец коммента не удалось найти
          // - Предупреждения?
          // - Предупреждения должны храниться в ParsedFileItem, чтоб их можно было показать визуально
          if sub_section.IsInvalid then continue;
          
          if sub_section.StartsWith(not_really_comment_start) then
            is_directive := true else
          begin
            var space_left := false;
            
            if (sub_section.i1>used_head.i1) and char.IsWhiteSpace(used_head.text[sub_section.i1-1]) then
            begin
              while (sub_section.i1>used_head.i1) and char.IsWhiteSpace(used_head.text[sub_section.i1-1]) do sub_section.i1 -= 1;
              if not space_left then
              begin
                sub_section.i1 += 1;
                space_left := true;
              end;
            end;
            
            if (sub_section.i2<used_head.i2) and char.IsWhiteSpace(used_head.text[sub_section.i2]) then
            begin
              while (sub_section.i2<used_head.i2) and char.IsWhiteSpace(used_head.text[sub_section.i2]) do sub_section.i2 += 1;
              if not space_left then
              begin
                sub_section.i2 -= 1;
//                space_left := true;
              end;
            end;
            
          end;
          
        end else
        begin
          sub_section := stopper_validator(kw, sub_section, used_head);
          if sub_section.IsInvalid then continue;
        end;
        
        try
          used_head.WithI2(sub_section.i1);
        except
          Writeln;
        end;
        // Handle unused text
        var unused_text := used_head.WithI2(sub_section.i1);
        if unused_text.Length<>0 then
          self.parts.Add( new MiscTextBlock(unused_text, f, MiscTextBlock.MiscText) );
        
        // Apply found block
        if is_comment then
        begin
          parts.Add(new MiscTextBlock(sub_section, f,
            if is_directive then
              MiscTextBlock.Directive else
              MiscTextBlock.Comment
          ));
        end else
        begin
          found_stopper_kw := kw;
          found_stopper_section := sub_section;
          exit;
        end;
        
        read_head := read_head.WithI1(sub_section.i2);
        used_head := read_head;
      end;
      
    end;
    
    //ToDo Убрать
//    public constructor(text: TextSection; f: ParsedPasFile; stoppers: sequence of string; stopper_validator: TextSection->TextSection; var found_stopper: TextSection);
//    begin
//      inherited Create(f);
//      var expected_sub_strs := (stoppers + comment_end_dict.Keys).ToArray;
//      
//      while true do
//      begin
//        var sub_section := text.SubSectionOfFirst(expected_sub_strs);
//        var sub_string := if sub_section.IsInvalid then nil else sub_section.ToString;
//        
//        if (sub_string<>nil) and not comment_end_dict.ContainsKey(sub_string) then
//        begin
//          //ToDo Всё не так - надо бы переписать вообще...
//          // - Когда валидатор не сработал - следующий поиск должен начаться после sub_section
//          // - Но при этом text_before должен начинаться с конца применённого текста
//          sub_section := stopper_validator(sub_section);
//          sub_string := if sub_section.IsInvalid then nil else sub_section.ToString;
//        end;
//        
//        var text_before := text;
//        if not sub_section.IsInvalid then
//          text_before.i2 := sub_section.i1;
//        if text_before.Length<>0 then
//          self.parts += new MiscTextBlock(text_before, f, false) as JTextBlockPart;
//        
//        // Nothing found
//        if sub_string=nil then
//        begin
//          found_stopper := TextSection.Invalid;
//          break;
//        end else
//        
//        // Found comment: Add comment text and then text.Trim
//        if comment_end_dict.ContainsKey(sub_string) then
//        begin
//          sub_section.i2 := text.i2;
//          sub_section := sub_section.TrimEndAfter(
//            comment_end_dict[sub_string]
//          );
//          
//          if sub_section.IsInvalid then raise new System.InvalidOperationException(text.ToString);
//          if not sub_section.StartsWith('{$') then // Не очень красиво - но надо для директив
//            while (sub_section.i2<text.i2) and char.IsWhiteSpace(text.text[sub_section.i2]) do sub_section.i2 += 1;
//          
//          self.parts += new MiscTextBlock(sub_section, f, true) as JTextBlockPart;
//          text.i1 := sub_section.i2;
//        end else
//        
//        // Found stopper: return it
//        begin
//          found_stopper := sub_section;
//          break;
//        end;
//        
//      end;
//      
//    end;
    
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override := parts.Cleanup(is_invalid);
    protected procedure AddDirectChildrenTo(l: List<MinimizableNode>); override := l += parts;
    
    public procedure UnWrapTo(sw: System.IO.StreamWriter; need_node: MinimizableNode->boolean); override :=
    foreach var part in parts.EnmrDirect do
      if (need_node=nil) or need_node(part) then
        part.UnWrapTo(sw, need_node);
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := 0;
      foreach var part in parts.EnmrDirect do
        if (need_node=nil) or need_node(part) then
          Result += part.CountLines(need_node);
    end;
    
    public function ToString: string; override;
    begin
      var res := new StringBuilder;
      res += 'Batch of text:'#10;
      foreach var part in parts.EnmrDirect do
      begin
//        res += #9;
        res += part.ToString;
        res += #10;
      end;
      Result := res.ToString;
    end;
    
  end;
  
  // Cleans up to be a single whitespace
  SpacingBlock = sealed class
    private missing_space: MissingTextBlock;
    private extra_space: MiscTextBlock;
    private final_space: char := ' ';
    
    public property IsMissing: boolean read missing_space<>nil;
    public property IsEmpty: boolean read (missing_space=nil) and (extra_space=nil);
    
    private constructor(text: TextSection; f: ParsedPasFile);
    begin
      
      if text.Length=0 then
        missing_space := new MissingTextBlock('WhiteSpace', f) else
      if text.Length>1 then
        extra_space := new MiscTextBlock(text, f, MiscTextBlock.MiscText) else
        final_space := text[0];
      
    end;
    
    public static function ReadStart(var ptext: TextSection; f: ParsedPasFile): SpacingBlock;
    begin
      var text := ptext;
      
      var ind := 0;
      var max_len := text.Length;
      while (ind<max_len) and char.IsWhiteSpace(text[ind]) do
        ind += 1;
      ptext := text.TrimStart(ind);
      
      Result := new SpacingBlock(text.TakeFirst(ind), f);
    end;
    
    protected procedure Cleanup(is_invalid: MinimizableNode->boolean);
    begin
      if MinimizableNode.ApplyCleanup(missing_space, is_invalid) then
        missing_space := nil else
      if MinimizableNode.ApplyCleanup(extra_space, is_invalid) then
      begin
        final_space := extra_space.text[0];
        extra_space := nil;
      end;
    end;
    protected procedure AddDirectChildrenTo(l: List<MinimizableNode>);
    begin
      if missing_space<>nil then l += missing_space;
      if   extra_space<>nil then l +=   extra_space;
    end;
    
    public procedure UnWrapTo(sw: System.IO.StreamWriter; need_node: MinimizableNode->boolean);
    begin
      if MinimizableNode.ApplyNeedNode(extra_space, need_node) then
        sw.Write( extra_space.text.ToString ) else
      if MinimizableNode.ApplyNeedNode(missing_space, need_node) then
        {Write missing space aka nothing} else
        sw.Write( final_space );
    end;
    public function CountLines(need_node: MinimizableNode->boolean) :=
    if MinimizableNode.ApplyNeedNode(extra_space, need_node) then extra_space.CountLines(need_node) else
    if MinimizableNode.ApplyNeedNode(missing_space, need_node) then 0 else
      integer( final_space=#10 );
    
    public function ToString: string; override :=
    if missing_space<>nil then
      'Missing' else
    if extra_space<>nil then
      'Extra:'+extra_space.text.ToString else
      'Perfect:#'+integer( final_space );
    
  end;
  
  {$endregion Text}
  
  {$region Common}
  
  CommonParsedItem = abstract class(ParsedFileItem)
    protected pretext: JTextBlock;
    
    public constructor(pretext: JTextBlock; f: ParsedPasFile);
    begin
      inherited Create(f);
      self.pretext := pretext;
    end;
    private constructor := raise new System.InvalidOperationException;
    
    protected procedure CommonCleanupBody(is_invalid: MinimizableNode->boolean); abstract;
    protected procedure CommonAddDirectChildrenTo(l: List<MinimizableNode>); abstract;
    
    public procedure CommonUnWrapTo(sw: System.IO.StreamWriter; need_node: MinimizableNode->boolean); abstract;
    public function CommonCountLines(need_node: MinimizableNode->boolean): integer; abstract;
    
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override;
    begin
      if (pretext<>nil) and is_invalid(pretext) then pretext := nil;
      CommonCleanupBody(is_invalid);
    end;
    
    protected procedure AddDirectChildrenTo(l: List<MinimizableNode>); override;
    begin
      if pretext<>nil then l += pretext;
      CommonAddDirectChildrenTo(l);
    end;
    
    public procedure UnWrapTo(sw: System.IO.StreamWriter; need_node: MinimizableNode->boolean); override;
    begin
      if (pretext<>nil) and ((need_node=nil) or need_node(pretext)) then pretext.UnWrapTo(sw, need_node);
      CommonUnWrapTo(sw, need_node);
    end;
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result += 0;
      if (pretext<>nil) and ((need_node=nil) or need_node(pretext)) then
        Result += pretext.CountLines(need_node);
      Result += CommonCountLines(need_node);
    end;
    
  end;
  
  EmptyCommonParsedItem = sealed class(CommonParsedItem)
    
    protected procedure CommonCleanupBody(is_invalid: MinimizableNode->boolean); override := exit;
    protected procedure CommonAddDirectChildrenTo(l: List<MinimizableNode>); override := exit;
    
    public procedure CommonUnWrapTo(sw: System.IO.StreamWriter; need_node: MinimizableNode->boolean); override := exit;
    public function CommonCountLines(need_node: MinimizableNode->boolean): integer; override := 0;
    
    public function ToString: string; override := pretext.ToString;
    
  end;
  
  {$endregion Common}
  
  {$region MRCD}
  
  MRCDValue = sealed auto class
    public ValidateKW: (TextSection, TextSection)->TextSection;
    public MakeNew: (JTextBlock, TextSection, ParsedPasFile) -> CommonParsedItem;
  end;
  MidReadCreationDict = sealed class
    private d := new Dictionary<string, MRCDValue>;
    
    public function Add(keywords: array of string; val: MRCDValue): MidReadCreationDict;
    begin
      foreach var kw in keywords do
        d.Add(kw.ToUpper, val);
      Result := self;
    end;
    public function Add(val: (array of string, MRCDValue)) := Add(val[0], val[1]);
    
    public function ReadSection(text: TextSection; f: ParsedPasFile; on_item: CommonParsedItem->()): JTextBlock;
    begin
      while true do
      begin
        var found_stopper_kw: string;
        var found_stopper_section: TextSection;
        Result := new JTextBlock(text, f, d.Keys, (kw, section, text)->d[kw].ValidateKW(section, text), found_stopper_kw, found_stopper_section);
        
        if Result.parts.IsEmpty then Result := nil;
        if found_stopper_kw=nil then break;
        
        on_item( d[found_stopper_kw].MakeNew(Result, found_stopper_section, f) );
//        Result := nil; // Will be overridden anyway
        
        text := text.WithI1(found_stopper_section.i2);
      end;
    end;
    
  end;
  
  {$endregion MRCD}
  
  {$region Operator}
  
  {$endregion Operator}
  
  {$region Method}
  
  {$endregion Method}
  
  {$region Type}
  
  {$endregion Type}
  
  {$region FileSections}
  
  PFHeader = sealed class(CommonParsedItem)
    
    private kw, body: TextSection;
    public constructor(pretext: JTextBlock; text: TextSection; f: ParsedPasFile);
    begin
      inherited Create(pretext, f);
      
      var ind := text.IndexOf(' ');
      if ind.IsInvalid then
      begin
        // ## Header
        kw := text;
        body := TextSection.Invalid;
      end else
      begin
        kw := text.TakeFirst(ind);
        body := text.TrimStart(ind+1).TrimEnd(';');
      end;
      
    end;
    
    public static keywords := |'##', 'program', 'unit', 'library', 'namespace'|;
    public static function ValidateKW(section, text: TextSection): TextSection;
    begin
      Result := TextSection.Invalid;
      
      if (section.i1 > text.i1) and not char.IsWhiteSpace(section.text[section.i1-1]) then
        exit;
      
      if section = '##' then
      begin
        
        // ## => ###
        if (section.i2 < text.i2) and (section.WithI2(section.i2+1) = '###') then
          section.i2 += 1;
        
        if (section.i2 < text.i2) and (section.text[section.i2] <> ' ') then
          exit;
        
      end else
      begin
        
        if section.i2 = text.i2 then exit;
        if section.text[section.i2] <> ' ' then
          exit;
        
        section := section.WithI2(text.i2).TrimAfterFirst(';');
        if section.IsInvalid then exit;
        
      end;
      
      Result := section;
    end;
    public static function MakeNew(pretext: JTextBlock; text: TextSection; f: ParsedPasFile): CommonParsedItem := new PFHeader(pretext, text, f);
    public static mrcd_value := (keywords, new MRCDValue(ValidateKW, MakeNew));
    
    protected procedure CommonCleanupBody(is_invalid: MinimizableNode->boolean); override := exit;
    protected procedure CommonAddDirectChildrenTo(l: List<MinimizableNode>); override := exit;
    
    public procedure CommonUnWrapTo(sw: System.IO.StreamWriter; need_node: MinimizableNode->boolean); override;
    begin
      sw.Write(kw.ToString);
      if not body.IsInvalid then
      begin
        sw.Write(' ');
        sw.Write(body.ToString);
        sw.Write(';');
      end;
    end;
    
    public function CommonCountLines(need_node: MinimizableNode->boolean): integer; override := body.CountOf(#10);
    
    public function ToString: string; override;
    begin
      var res := new StringBuilder;
      if pretext<>nil then
        res += pretext.ToString;
      res += $'File header: KeyWord[{kw}] Body[{body}]';
      Result := res.ToString;
    end;
    
  end;
  
  PFUsedUnit = sealed class(ParsedFileItem)
    
    private space1: SpacingBlock;
    private name: TextSection;
    private space2: SpacingBlock;
    private const in_separator = 'in';
    private space3: SpacingBlock;
    private in_path: TextSection := TextSection.Invalid;
    private space4: MiscTextBlock;
    
    public constructor(text: TextSection; f: ParsedPasFile);
    begin
      inherited Create(f);
      
      self.space1 := SpacingBlock.ReadStart(text, f);
      self.space4 := MiscTextBlock.ReadEndSpaces(text, f);
      self.name := text;
      
      var ind := text.IndexOf(char.IsWhiteSpace);
      if ind.IsInvalid then exit;
      var name := text.TakeFirst(ind);
      text := text.TrimStart(ind);
      
      // Find "in"
      
      var space2 := SpacingBlock.ReadStart(text, f);
      if not text.StartsWith(in_separator) then exit;
      text := text.TrimStart(in_separator.Length);
      
      // Find path literal
      
      var space3 := SpacingBlock.ReadStart(text, f);
      var in_path := text;
      
      // Cleanup
      
      self.name := name;
      self.space2 := space2;
      self.space3 := space3;
      self.in_path := in_path;
      
    end;
    
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override;
    begin
      space1.Cleanup(is_invalid);
      space2.Cleanup(is_invalid);
      space3.Cleanup(is_invalid);
      if ApplyCleanup(space4, is_invalid) then space4 := nil;
    end;
    protected procedure AddDirectChildrenTo(l: List<MinimizableNode>); override;
    begin
      space1.AddDirectChildrenTo(l);
      space2.AddDirectChildrenTo(l);
      space3.AddDirectChildrenTo(l);
      if space4<>nil then l += space4;
    end;
    
    public procedure UnWrapTo(sw: System.IO.StreamWriter; need_node: MinimizableNode->boolean); override;
    begin
      space1.UnWrapTo(sw, need_node);
      sw.Write(name.ToString);
      if not in_path.IsInvalid then
      begin
        space2.UnWrapTo(sw, need_node);
        sw.Write(in_separator);
        space3.UnWrapTo(sw, need_node);
        sw.Write(in_path.ToString);
      end;
      if ApplyNeedNode(space4, need_node) then
        space4.UnWrapTo(sw, need_node);
    end;
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := 0;
      Result += space1.CountLines(need_node);
      Result += space2.CountLines(need_node);
      Result += space3.CountLines(need_node);
      if ApplyNeedNode(space4, need_node) then
        Result += space4.CountLines(need_node);
    end;
    
    public function ToString: string; override;
    begin
      var res := new StringBuilder;
      res += if in_path.IsInvalid then 'UsedUnit' else 'UsedInUnit';
      res += ':';
      
      res += ' Spacing[';
      res += space1.ToString;
      res += ']';
      
      res += ' Name[';
      res += name.ToString;
      res += ']';
      
      if not in_path.IsInvalid then
      begin
        
        res += ' Spacing[';
        res += space2.ToString;
        res += ']';
        
        res += ' ';
        res += in_separator;
        res += ' ';
        
        res += ' Spacing[';
        res += space3.ToString;
        res += ']';
        
        res += ' Path[';
        res += in_path.ToString;
        res += ']';
        
      end;
      
      if space4<>nil then
      begin
        res += ' [';
        res += space4.text.ToString;
        res += ']';
      end;
      
      Result := res.ToString;
    end;
    
  end;
  PFUsesSection = sealed class(CommonParsedItem)
    
    private used_units := new MinimizableNodeList<PFUsedUnit>;
    public constructor(pretext: JTextBlock; text: TextSection; f: ParsedPasFile);
    begin
      inherited Create(pretext, f);
      text := text
        .TrimStart( text.IndexOf(' ') ) // 1 space left, same as after each ","
        .TrimEnd(';')
      ;
      
      while true do
      begin
        var ind := text.IndexOf(',');
        if ind.IsInvalid then break;
        used_units += new PFUsedUnit(text.TakeFirst(ind), f);
        text := text.TrimStart(ind+1);
      end;
      used_units += new PFUsedUnit(text, f);
      
    end;
    
    public static keywords := |'uses'|;
    public static function ValidateKW(section, text: TextSection): TextSection;
    begin
      Result := TextSection.Invalid;
      
      if (section.i1 > text.i1) and not char.IsWhiteSpace(section.text[section.i1-1]) then exit;
      if section.i2=text.i2 then exit;
      if section.text[section.i2] <> ' ' then exit;
      
      Result := section.WithI2(text.i2).TrimAfterFirst(';');
    end;
    public static function MakeNew(pretext: JTextBlock; text: TextSection; f: ParsedPasFile): CommonParsedItem := new PFUsesSection(pretext, text, f);
    public static mrcd_value := (keywords, new MRCDValue(ValidateKW, MakeNew));
    
    protected procedure CommonCleanupBody(is_invalid: MinimizableNode->boolean); override :=
    used_units.Cleanup(is_invalid);
    protected procedure CommonAddDirectChildrenTo(l: List<MinimizableNode>); override :=
    l += used_units;
    
    public procedure CommonUnWrapTo(sw: System.IO.StreamWriter; need_node: MinimizableNode->boolean); override;
    begin
      sw.Write('uses');
      foreach var uu in used_units.EnmrDirect do
        if ApplyNeedNode(uu, need_node) then
          uu.UnWrapTo(sw, need_node);
      sw.Write(';');
    end;
    
    public function CommonCountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := 0;
      foreach var uu in used_units.EnmrDirect do
        if ApplyNeedNode(uu, need_node) then
          Result += uu.CountLines(need_node);
    end;
    
    public function ToString: string; override;
    begin
      var res := new StringBuilder;
      if pretext<>nil then
        res += pretext.ToString;
      res += 'Uses section:'#10;
      foreach var uu in used_units.EnmrDirect do
      begin
        res += #9;
        res += uu.ToString;
      end;
      Result := res.ToString;
    end;
    
  end;
  
  {$endregion FileSections}
  
{$region ParsedPasFile}

type
  ParsedPasFile = partial sealed class(ParsedFile)
    private body := new MinimizableNodeList<CommonParsedItem>;
    
    private static whole_file_mrcd := MidReadCreationDict.Create
      .Add(PFHeader.mrcd_value)
      .Add(PFUsesSection.mrcd_value)
    ;
    
  end;
  
constructor ParsedPasFile.Create(fname, base_dir, target: string);
begin
  inherited Create(fname, base_dir, target);
  var text := new TextSection( ReadAllText(fname).Replace(#13#10,#10).Replace(#13,#10) );
  
  var last_jtb := whole_file_mrcd.ReadSection(text, self, self.body.Add);
  if last_jtb<>nil then self.body.Add( new EmptyCommonParsedItem(last_jtb, self) );
  
  foreach var cpi in body.EnmrDirect do
  begin
    Writeln(cpi);
  end;
  
end;

procedure ParsedPasFile.CleanupBody(is_invalid: MinimizableNode->boolean) := body.Cleanup(is_invalid);
procedure ParsedPasFile.AddDirectChildrenTo(l: List<MinimizableNode>) := l += body;

procedure ParsedPasFile.UnWrapTo(new_base_dir: string; need_node: MinimizableNode->boolean);
begin
  var sw := new System.IO.StreamWriter(
    System.IO.Path.Combine(new_base_dir, self.rel_fname),
    false, write_enc
  );
  
  try
    foreach var cpi in body.EnmrDirect do
      cpi.UnWrapTo(sw, need_node);
  finally
    sw.Close;
  end;
  
end;

function ParsedPasFile.CountLines(need_node: MinimizableNode->boolean): integer;
begin
  Result := 1;
  
  foreach var cpi in body.EnmrDirect do
    Result += cpi.CountLines(need_node);
  
end;

{$endregion ParsedPasFile}

function ParseFile(fname, base_dir, target: string) := new ParsedPasFile(fname, base_dir, target);

begin
  ParsedFile.ParseByExt.Add('.pas', ParseFile);
end.