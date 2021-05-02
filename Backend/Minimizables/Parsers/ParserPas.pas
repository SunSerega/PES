unit ParserPas;
{$string_nullbased+}

//ToDo Пройтись по всем ToDo

//ToDo Предупреждения
//ToDo Визуальная часть
// - И удалить .ToString-и отдельным коммитом, когда будет визуал
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
    
    protected procedure FillBodyChangedSections(need_node: MinimizableNode->boolean; deleted: List<TextSection>; added: List<AddedText>); override;
    protected procedure FillBodyPointAreasList(ind: StringIndex; l: List<PointAreasList>); override;
    
  end;
  
implementation

type
  
  {$region Text}
  
  MiscTextBlock = sealed class(ParsedFileItem)
    private text_type: string;
    
    public const  MiscText = 'MiscText';
    public const   Comment = 'Comment';
    public const Directive = 'Directive';
    
    public constructor(text: TextSection; f: ParsedPasFile; text_type: string);
    begin
      inherited Create(f, text);
      if text.Length=0 then raise new System.InvalidOperationException;
      self.text_type := text_type;
      
      case text_type of
         MiscText: if not original_section.IsWhiteSpace then ; //ToDo предупреждение
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
    
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override := exit;
    protected procedure AddDirectChildrenTo(l: List<MinimizableNode>); override := exit;
    
    public procedure UnWrapTo(sw: System.IO.StreamWriter; need_node: MinimizableNode->boolean); override := sw.Write( original_section.ToString );
    public function CountLines(need_node: MinimizableNode->boolean): integer; override := original_section.CountOf(#10);
    
    protected procedure FillBodyChangedSections(need_node: MinimizableNode->boolean; deleted: List<TextSection>; added: List<AddedText>); override := exit;
    protected procedure FillBodyPointAreasList(ind: StringIndex; l: List<PointAreasList>); override := exit;
    
    public function ToString: string; override :=
    $'{self.f}:{text_type} >>>{original_section}<<<';
    
  end;
  MissingTextBlock = sealed class(MinimizableNode)
    private missing_ind: StringIndex;
    private descr: string;
    
    public constructor(missing_ind: StringIndex; descr: string);
    begin
      self.missing_ind := missing_ind;
      self.descr := descr;
    end;
    
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override := exit;
    protected procedure AddDirectChildrenTo(l: List<MinimizableNode>); override := exit;
    
    protected procedure FillChangedSections(need_node: MinimizableNode->boolean; deleted: List<TextSection>; added: List<AddedText>) :=
    if not need_node(self) then added += new AddedText(missing_ind, descr);
    protected function FillPointAreasList(ind: StringIndex; var l: PointAreasList): boolean;
    begin
      Result := ind = missing_ind;
      if not Result then exit;
      //ToDo Вообще плохо что nil... В идеале вообще удалить поле text из TextSection и передавать строку параметром, а то куча лишнего делается
      l := new PointAreasList(new TextSection(nil, missing_ind, missing_ind));
    end;
    
    public function ToString: string; override := $'~~~ Missing[{descr}]<<<';
    
  end;
  
  JTextBlock = sealed class(ParsedFileItem)
    private parts := new MinimizableNodeList<MiscTextBlock>;
    private static comment_end_dict := new Dictionary<string, string>;
    private const not_really_comment_start = '{$';
    private const literal_string_start: string = '''';
    
    static constructor;
    begin
      comment_end_dict := '{~} //~'#10' (*~*)'.ToWords
        .Select(w->w.Split(|'~'|,2))
        .ToDictionary(w->w[0], w->w[1]);
    end;
    
    public constructor(text: TextSection; f: ParsedPasFile; stoppers: sequence of string; stopper_validator: (string, TextSection, TextSection)->TextSection; var found_stopper_kw: string; var found_stopper_section: TextSection);
    begin
      inherited Create(f, text);
      var expected_sub_strs := (stoppers + comment_end_dict.Keys + |literal_string_start|).ToArray;
      
      var used_head := text;
      var read_head := text;
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
          sub_section := sub_section.WithI2(read_head.i2).TrimAfterFirst(
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
    
    protected procedure FillBodyChangedSections(need_node: MinimizableNode->boolean; deleted: List<TextSection>; added: List<AddedText>); override :=
    foreach var part in parts.EnmrDirect do part.FillChangedSections(need_node, deleted, added);
    protected procedure FillBodyPointAreasList(ind: StringIndex; l: List<PointAreasList>); override :=
    foreach var part in parts.EnmrDirect do
    begin
      var sub_l := default(PointAreasList);
      if part.FillPointAreasList(ind, sub_l) then
        l += sub_l;
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
    
    private constructor(text: TextSection; f: ParsedPasFile; missing_descr: string := 'Whitespace');
    begin
      
      if text.Length=0 then
        missing_space := new MissingTextBlock(text.i1, missing_descr) else
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
        final_space := extra_space.original_section[0];
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
        sw.Write( extra_space.original_section.ToString ) else
      if MinimizableNode.ApplyNeedNode(missing_space, need_node) then
        {Write missing space aka nothing} else
        sw.Write( final_space );
    end;
    public function CountLines(need_node: MinimizableNode->boolean) :=
    if MinimizableNode.ApplyNeedNode(extra_space, need_node) then extra_space.CountLines(need_node) else
    if MinimizableNode.ApplyNeedNode(missing_space, need_node) then 0 else
      integer( final_space=#10 );
    
    protected procedure FillChangedSections(need_node: MinimizableNode->boolean; deleted: List<TextSection>; added: List<AddedText>);
    begin
      if missing_space<>nil then missing_space.FillChangedSections(need_node, deleted, added);
      if extra_space<>nil   then extra_space  .FillChangedSections(need_node, deleted, added);
    end;
    protected function FillPointAreasList(ind: StringIndex; var l: PointAreasList) :=
    missing_space.FillPointAreasList(ind, l) or
    extra_space.FillPointAreasList(ind, l);
    
    public function ToString: string; override :=
    if missing_space<>nil then
      'Missing' else
    if extra_space<>nil then
      'Extra:'+extra_space.original_section.ToString else
      'Perfect:#'+integer( final_space );
    
  end;
  
  {$endregion Text}
  
  {$region Common}
  
  CommonParsedItem = abstract class(ParsedFileItem)
    protected pretext: JTextBlock;
    protected original_section: TextSection;
    
    public constructor(pretext: JTextBlock; original_section: TextSection; f: ParsedPasFile);
    begin
      inherited Create(f, original_section.WithI1(pretext.original_section.i1));
      self.pretext := pretext;
      self.original_section := original_section;
    end;
    private constructor := raise new System.InvalidOperationException;
    
    protected procedure CommonCleanupBody(is_invalid: MinimizableNode->boolean); abstract;
    protected procedure CommonAddDirectChildrenTo(l: List<MinimizableNode>); abstract;
    
    public procedure CommonUnWrapTo(sw: System.IO.StreamWriter; need_node: MinimizableNode->boolean); abstract;
    public function CommonCountLines(need_node: MinimizableNode->boolean): integer; abstract;
    
    protected procedure CommonFillBodyChangedSections(need_node: MinimizableNode->boolean; deleted: List<TextSection>; added: List<AddedText>); abstract;
    protected procedure CommonFillBodyPointAreasList(ind: StringIndex; l: List<PointAreasList>); abstract;
    
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
    
    protected procedure FillBodyChangedSections(need_node: MinimizableNode->boolean; deleted: List<TextSection>; added: List<AddedText>); override;
    begin
      if pretext<>nil then pretext.FillChangedSections(need_node, deleted, added);
      CommonFillBodyChangedSections(need_node, deleted, added);
    end;
    protected procedure FillBodyPointAreasList(ind: StringIndex; l: List<PointAreasList>); override;
    begin
      var sub_l := default(PointAreasList);
      if (pretext<>nil) and pretext.FillPointAreasList(ind, sub_l) then
        l += sub_l else
        CommonFillBodyPointAreasList(ind, l);
    end;
    
  end;
  
  EmptyCommonParsedItem = sealed class(CommonParsedItem)
    
    public constructor(pretext: JTextBlock; f: ParsedPasFile) :=
    inherited Create(pretext, pretext.original_section.TakeLast(0), f);
    
    protected procedure CommonCleanupBody(is_invalid: MinimizableNode->boolean); override := exit;
    protected procedure CommonAddDirectChildrenTo(l: List<MinimizableNode>); override := exit;
    
    public procedure CommonUnWrapTo(sw: System.IO.StreamWriter; need_node: MinimizableNode->boolean); override := exit;
    public function CommonCountLines(need_node: MinimizableNode->boolean): integer; override := 0;
    
    protected procedure CommonFillBodyChangedSections(need_node: MinimizableNode->boolean; deleted: List<TextSection>; added: List<AddedText>); override := exit;
    protected procedure CommonFillBodyPointAreasList(ind: StringIndex; l: List<PointAreasList>); override := exit;
    
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
      inherited Create(pretext, text, f);
      
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
    
    protected procedure CommonFillBodyChangedSections(need_node: MinimizableNode->boolean; deleted: List<TextSection>; added: List<AddedText>); override := exit;
    protected procedure CommonFillBodyPointAreasList(ind: StringIndex; l: List<PointAreasList>); override := exit;
    
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
      inherited Create(f, text);
      
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
    
    protected procedure FillBodyChangedSections(need_node: MinimizableNode->boolean; deleted: List<TextSection>; added: List<AddedText>); override;
    begin
      if space1<>nil then space1.FillChangedSections(need_node, deleted, added);
      if space2<>nil then space2.FillChangedSections(need_node, deleted, added);
      if space3<>nil then space3.FillChangedSections(need_node, deleted, added);
      if space4<>nil then space4.FillChangedSections(need_node, deleted, added);
    end;
    protected procedure FillBodyPointAreasList(ind: StringIndex; l: List<PointAreasList>); override;
    begin
      var sub_l := default(PointAreasList);
      if (space1<>nil) and space1.FillPointAreasList(ind, sub_l) then l+=sub_l else
      if (space2<>nil) and space2.FillPointAreasList(ind, sub_l) then l+=sub_l else
      if (space3<>nil) and space3.FillPointAreasList(ind, sub_l) then l+=sub_l else
      if (space4<>nil) and space4.FillPointAreasList(ind, sub_l) then l+=sub_l else
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
        res += space4.original_section.ToString;
        res += ']';
      end;
      
      Result := res.ToString;
    end;
    
  end;
  PFUsesSection = sealed class(CommonParsedItem)
    
    private used_units := new MinimizableNodeList<PFUsedUnit>;
    public constructor(pretext: JTextBlock; text: TextSection; f: ParsedPasFile);
    begin
      inherited Create(pretext, text, f);
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
    
    protected procedure CommonFillBodyChangedSections(need_node: MinimizableNode->boolean; deleted: List<TextSection>; added: List<AddedText>); override :=
    foreach var uu in used_units.EnmrDirect do uu.FillChangedSections(need_node, deleted, added);
    protected procedure CommonFillBodyPointAreasList(ind: StringIndex; l: List<PointAreasList>); override :=
    foreach var uu in used_units.EnmrDirect do
    begin
      var sub_l := default(PointAreasList);
      if uu.FillPointAreasList(ind, sub_l) then
      begin
        l += sub_l;
        break;
      end;
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
  var text := new TextSection( self.original_text );
  
  var last_jtb := whole_file_mrcd.ReadSection(text, self, self.body.Add);
  if last_jtb<>nil then self.body.Add( new EmptyCommonParsedItem(last_jtb, self) );
  
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
      if ApplyNeedNode(cpi, need_node) then
        cpi.UnWrapTo(sw, need_node);
  finally
    sw.Close;
  end;
  
end;

function ParsedPasFile.CountLines(need_node: MinimizableNode->boolean): integer;
begin
  Result := 1;
  
  foreach var cpi in body.EnmrDirect do
    if ApplyNeedNode(cpi, need_node) then
      Result += cpi.CountLines(need_node);
  
end;

procedure ParsedPasFile.FillBodyChangedSections(need_node: MinimizableNode->boolean; deleted: List<TextSection>; added: List<AddedText>) :=
foreach var cpi in body.EnmrDirect do cpi.FillChangedSections(need_node, deleted, added);

procedure ParsedPasFile.FillBodyPointAreasList(ind: StringIndex; l: List<PointAreasList>) :=
foreach var cpi in body.EnmrDirect do
begin
  var sub_l := default(PointAreasList);
  if cpi.FillPointAreasList(ind, sub_l) then
  begin
    l += sub_l;
    break; // Не обязательно, но в .pas файлах (пока) нет пересекающихся областей
  end;
end;

{$endregion ParsedPasFile}

function ParseFile(fname, base_dir, target: string) := new ParsedPasFile(fname, base_dir, target);

begin
  ParsedFile.ParseByExt.Add('.pas', ParseFile);
end.