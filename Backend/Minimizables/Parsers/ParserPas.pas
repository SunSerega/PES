unit ParserPas;
{$string_nullbased+}

//ToDo Следующее: PFMethod
//ToDo Сохранение информации со стадии валидации?
//ToDo Визуал предупреждений
//ToDo Пройтись по всем ToDo

interface

uses MinimizableCore in '..\..\MinimizableCore';
uses ParserCore;

type
  
  ParsedPasFile = partial sealed class(ParsedFile)
    
    public constructor(fname, base_dir, target: string);
    
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override;
    protected procedure AddDirectChildrenTo(l: VulnerableNodeList); override;
    
    public procedure UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override;
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    
    protected procedure FillChangedSectionsBody(need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override;
    protected procedure FillIndexAreasBody(ind: StringIndex; l: List<SIndexRange>); override;
    
  end;
  
implementation

function CharIsNamePart(ch: char) := ch.IsLetter or ch.IsDigit or (ch in '&_');

type
  
  {$region Text}
  
  MiscTextType = (TT_WhiteSpace, TT_Comment, TT_Directive, TT_Name);
  MiscTextBlock = sealed class(ParsedFileItem)
    private range: SIndexRange;
    private text_type: MiscTextType;
    
    public constructor(text: StringSection; f: ParsedPasFile; text_type: MiscTextType);
    begin
      inherited Create(f, text.Length);
      if text.Length=0 then raise new System.InvalidOperationException;
      self.range := text.range;
      self.text_type := text_type;
      
      case text_type of
        TT_WhiteSpace: if not text.All(char.IsWhiteSpace) then AddWarning(text, 'Expected only whitespaces');
           TT_Comment: ;
         TT_Directive: ;
              TT_Name: ;
        else raise new System.InvalidOperationException(text_type.ToString);
      end;
      
    end;
    
    public function MakeStringSection := new StringSection(GetOriginalText, range);
    
    public static function ReadStartSpaces(var text: StringSection; f: ParsedPasFile): MiscTextBlock;
    begin
      Result := nil;
      
      var space_section := text.TakeFirstWhile(char.IsWhiteSpace);
      if space_section.Length=0 then exit;
      text := text.WithI1(space_section.I2);
      
      Result := new MiscTextBlock(space_section, f, TT_WhiteSpace);
    end;
    public static function ReadEndSpaces(var text: StringSection; f: ParsedPasFile): MiscTextBlock;
    begin
      Result := nil;
      
      var space_section := text.TakeLastWhile(char.IsWhiteSpace);
      if space_section.Length=0 then exit;
      text := text.WithI2(space_section.I1);
      
      Result := new MiscTextBlock(space_section, f, TT_WhiteSpace);
    end;
    
    protected function FileCleanupBody(is_invalid: MinimizableNode->boolean): StringIndex; override := range.Length;
    protected procedure AddDirectChildrenTo(l: VulnerableNodeList); override := exit;
    
    public procedure UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override := tw.Write( MakeStringSection.ToString );
    public function CountLines(need_node: MinimizableNode->boolean): integer; override := MakeStringSection.CountOf(#10);
    
    protected procedure FillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override := exit;
    protected procedure FillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); override := exit;
    
  end;
  
  MissingTextBlock = sealed class(MinimizableNode)
    private descr: string;
    public constructor(descr: string) := self.descr := descr;
    
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override := raise new System.InvalidOperationException;
    protected procedure AddDirectChildrenTo(l: VulnerableNodeList); override := exit;
    
    protected procedure FillChangedSections(skipped: integer; need_node: MinimizableNode->boolean; added: List<AddedText>) :=
    if not need_node(self) then added += new AddedText(skipped, descr);
    protected function FillIndexAreas(var skipped: integer; ind: StringIndex; l: List<SIndexRange>): boolean;
    begin
      Result := ind = skipped;
      if not Result then exit;
      l += new SIndexRange(ind, ind);
    end;
    
  end;
  
  JTextBlock = sealed class(ParsedFileItem)
    private parts := new MinimizableNodeList<MiscTextBlock>;
    private static comment_end_dict := new Dictionary<string, string>;
    private const directive_start = '{$';
    private const literal_string_start: string = '''';
    
    static constructor;
    begin
      comment_end_dict := '{~} //~'#10' (*~*)'.ToWords
        .Select(w->w.Split(|'~'|,2))
        .ToDictionary(w->w[0], w->w[1]);
    end;
    
    private static function GetAllSubStrs(stoppers: sequence of string) := (stoppers + comment_end_dict.Keys + |literal_string_start|).ToArray;
    private static function TrySkipStringLiteral(text: StringSection; var _read_head: StringIndex; kw: string): boolean;
    begin
      Result := false;
      if kw <> literal_string_start then exit;
      var read_head := _read_head;
      
      while true do
      begin
        var ind := text.WithI1(read_head).IndexOf(literal_string_start);
        
        if ind.IsInvalid then
        begin
          {ToDo предупреждение незаконченной строки};
          exit;
        end;
        read_head += ind+literal_string_start.Length;
        
        if not text.WithI1(read_head).StartsWith(literal_string_start) then
          break;
        read_head += literal_string_start.Length;
      end;
      
      _read_head := read_head;
      Result := true;
    end;
    private static function TryExpandComment(text, sub_section: StringSection; kw: string): StringSection;
    begin
      Result := StringSection.Invalid;
      var comment_end: string;
      if not comment_end_dict.TryGetValue(kw, comment_end) then exit;
      
      sub_section := sub_section.WithI2(text.I2);
      Result := sub_section.TrimAfterFirst(comment_end);
      // Компилятор паскаля воспринимает конец файла как конец коммента
      if Result.IsInvalid then Result := sub_section;
      
    end;
    private static function TryFeedComment(text, section: StringSection): StringSection;
    begin
      Result := section;
      if section.StartsWith(directive_start) then exit;
      
      var space_left := false;
      var changed := false;
      
      while true do
      begin
        var ch := Result.Prev(text);
        if (ch=nil) or not char.IsWhiteSpace(ch.Value) then break;
        Result.range.i1 -= 1;
        changed := true;
      end;
      if changed then
      begin
        Result.range.i1 += 1;
        space_left := true;
      end;
      
      while true do
      begin
        var ch := Result.Next(text);
        if (ch=nil) or not char.IsWhiteSpace(ch.Value) then break;
        Result.range.i2 += 1;
        changed := true;
      end;
      if not space_left and changed then
        Result.range.i2 -= 1;
      
    end;
    
    public static procedure ValidateNextStopper(text: StringSection; stoppers: sequence of string; stopper_validator: function(kw: string; sub_section, whole_text: StringSection): StringSection; var found_stopper_kw: string; var found_stopper_range: SIndexRange);
    begin
      var expected_sub_strs := GetAllSubStrs(stoppers);
      
      var read_head := text.I1;
      var used_head := text.I1;
      while true do
      begin
        //ToDo Только одна из expected_sub_strs оказывается найдена
        var sub_section := text.WithI1(read_head).SubSectionOfFirst(expected_sub_strs);
        
        if sub_section.IsInvalid then
        begin
          found_stopper_kw := nil;
          exit;
        end;
//        read_head := sub_section.i2;
        read_head := sub_section.I1+1; //ToDo Вообще не вопрос, если бы .SubSectionOfFirst ловило все строки сразу, а так - скоре костыль
        
        var kw := sub_section.ToString.ToUpper;
        
        if TrySkipStringLiteral(text, read_head, kw) then continue;
        
        var expanded_section := TryExpandComment(text.WithI1(read_head), sub_section, kw);
        if expanded_section.IsInvalid then
        begin
          expanded_section := stopper_validator(kw, sub_section, text.WithI1(used_head));
          if expanded_section.IsInvalid then continue;
        end;
        
        // Apply found block
        if not comment_end_dict.ContainsKey(kw) then
        begin
          found_stopper_kw := kw;
          found_stopper_range := expanded_section.range;
          exit;
        end;
        
        read_head := expanded_section.I2;
        used_head := read_head;
      end;
      
    end;
    public constructor(text: StringSection; f: ParsedPasFile; stoppers: sequence of string; stopper_validator: function(kw: string; sub_section, whole_text: StringSection): StringSection; var found_stopper_kw: string; var found_stopper_range: SIndexRange);
    begin
      inherited Create(f, StringIndex.Invalid);
      var expected_sub_strs := GetAllSubStrs(stoppers);
      
//      var sw := Stopwatch.StartNew;
//      var write_time := procedure(help: string)->
//      if need_time then
//      begin
//        sw.Stop;
//        $'{sw.Elapsed}: {help}'.Println;
//        sw.Start;
//      end;
      
      var used_head := text.I1;
      var read_head := text.I1;
      while true do
      begin
//        write_time($'Before string search');
        var sub_section := text.WithI1(read_head).SubSectionOfFirst(expected_sub_strs);
        
//        if sub_section.IsInvalid then
//          write_time($'Failed to find: [{expected_sub_strs.JoinToString(''], ['')}]') else
//        begin
//          var sub_section0 := sub_section
//            .WithI1(Max(integer(sub_section.I1)-50, text.I1))
//            .WithI2(Min(integer(sub_section.I2)+50, text.I2))
//          ;
//          write_time($'After string search: [{sub_section}] at {sub_section.range}: [{sub_section0}]');
//        end;
          
        // Nothing found - add rest as text and exit
        if sub_section.IsInvalid then
        begin
          var rest_text := text.WithI1(used_head);
          if rest_text.Length<>0 then
            parts.Add(new MiscTextBlock(rest_text, f, TT_WhiteSpace));
          found_stopper_kw := nil;
          self.len := text.Length;
          exit;
        end;
        read_head := sub_section.I1+1;
        
        var kw := sub_section.ToString.ToUpper;
        
        if TrySkipStringLiteral(text, read_head, kw) then continue;
        
        // Expand sub_section to contain whole comment / whole code block
        // - Note: kw isn't updated
        var expanded_section := TryExpandComment(text.WithI1(read_head), sub_section, kw);
        if not expanded_section.IsInvalid then
          expanded_section := TryFeedComment(text.WithI1(used_head), expanded_section) else
        begin
          expanded_section := stopper_validator(kw, sub_section, text.WithI1(used_head));
          if expanded_section.IsInvalid then continue;
        end;
        
        // Handle unused text
        var unused_range := new SIndexRange(used_head, expanded_section.I1);
        if unused_range.Length<>0 then
          self.parts.Add( new MiscTextBlock(new StringSection(text.text, unused_range), f, TT_WhiteSpace) );
        
        // Apply found block
        if comment_end_dict.ContainsKey(kw) then
        begin
          parts.Add(new MiscTextBlock(expanded_section, f,
            if expanded_section.StartsWith(directive_start) then
              MiscTextType.TT_Directive else
              MiscTextType.TT_Comment
          ));
        end else
        begin
          found_stopper_kw := kw;
          found_stopper_range := expanded_section.range;
          self.len := text.WithI2(expanded_section.I1).Length;
          exit;
        end;
        
        read_head := expanded_section.I2;
        used_head := read_head;
      end;
      
    end;
    
    protected function FileCleanupBody(is_invalid: MinimizableNode->boolean): StringIndex; override;
    begin
      Result := FileListCleanup(parts, is_invalid);
      if Result=0 then Result := StringIndex.Invalid;
    end;
    protected procedure AddDirectChildrenTo(l: VulnerableNodeList); override := l += parts;
    
    public procedure UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override :=
    foreach var part in parts.EnmrDirect do
      if (need_node=nil) or need_node(part) then
        part.UnWrapTo(tw, need_node);
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := 0;
      foreach var part in parts.EnmrDirect do
        if (need_node=nil) or need_node(part) then
          Result += part.CountLines(need_node);
    end;
    
    protected procedure FillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override :=
    foreach var part in parts.EnmrDirect do
      part.FillChangedSections(skipped, need_node, deleted, added);
    protected procedure FillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); override :=
    foreach var part in parts.EnmrDirect do
      if part.FillIndexAreas(skipped, ind, l) then
        break;
    
  end;
  
  // Cleans up to be a single whitespace
  SpacingBlock = sealed class
    private missing_space: MissingTextBlock;
    private extra_space: MiscTextBlock;
    private final_space: char;
    
    public property IsMissing: boolean read missing_space<>nil;
    public property IsEmpty: boolean read (missing_space=nil) and (extra_space=nil);
    
    private constructor(text: StringSection; f: ParsedPasFile; final_space: char := ' ');
    begin
      self.final_space := final_space;
      
      if text.Length=0 then
        missing_space := new MissingTextBlock($'#{word(final_space)}') else
      begin
        if (text.Length>1) or (text[0]<>final_space) then
          extra_space := new MiscTextBlock(text, f, TT_WhiteSpace);
      end;
      
    end;
    
    public static function ReadStart(var text: StringSection; f: ParsedPasFile; final_space: char := ' '): SpacingBlock;
    begin
      var section := text.WithI2(text.I1).NextWhile(text.I2, char.IsWhiteSpace);
      text := text.WithI1(section.I2);
      Result := new SpacingBlock(section, f, final_space);
    end;
    public static function ReadEnd(var text: StringSection; f: ParsedPasFile; final_space: char := ' '): SpacingBlock;
    begin
      var section := text.WithI1(text.I2).PrevWhile(text.I1, char.IsWhiteSpace);
      text := text.WithI2(section.I1);
      Result := new SpacingBlock(section, f, final_space);
    end;
    
    protected function FileCleanup(is_invalid: MinimizableNode->boolean): integer;
    begin
      if (missing_space<>nil) and is_invalid(missing_space) then
        missing_space := nil else
      if (extra_space<>nil) and is_invalid(extra_space) then
        extra_space := nil;
      
      Result :=
        if extra_space<>nil then
          extra_space.range.Length else
          integer(missing_space=nil);
    end;
    protected procedure AddDirectChildrenTo(l: VulnerableNodeList);
    begin
      if missing_space<>nil then l += missing_space;
      if   extra_space<>nil then l +=   extra_space;
    end;
    
    public procedure UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean);
    begin
      if MinimizableNode.ApplyNeedNode(extra_space, need_node) then
        tw.Write( extra_space.MakeStringSection.ToString ) else
      if not MinimizableNode.ApplyNeedNode(missing_space, need_node) then
        tw.Write( final_space );
    end;
    public function CountLines(need_node: MinimizableNode->boolean) :=
    if MinimizableNode.ApplyNeedNode(extra_space, need_node) then extra_space.CountLines(need_node) else
    if MinimizableNode.ApplyNeedNode(missing_space, need_node) then 0 else
      integer( final_space=#10 );
    
    protected procedure FillChangedSections(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>);
    begin
      if extra_space<>nil then
        extra_space.FillChangedSections(skipped, need_node, deleted, added) else
      if missing_space<>nil then
        missing_space.FillChangedSections(skipped, need_node, added) else
        skipped += 1; // final_space
    end;
    protected function FillIndexAreas(var skipped: integer; ind: StringIndex; l: List<SIndexRange>): boolean;
    begin
      Result := true;
      if extra_space<>nil then
      begin
        if extra_space.FillIndexAreas(skipped, ind, l) then exit;
      end else
      if missing_space=nil then
      begin
        if ParsedFileItem.AddIndexArea(skipped, ind, final_space, l) then exit;
      end;
      Result := false;
    end;
    
  end;
  
  {$endregion Text}
  
  {$region MRCD}
  
  MidReadCreationDict = class;
  MRCDValue = sealed auto class
    public ValidateKW: function(section, whole_text: StringSection): StringSection;
    public MakeNew: function(text: StringSection; f: ParsedPasFile): ParsedFileItem;
    public Vampire: MidReadCreationDict;
  end;
  MidReadCreationDict = sealed class
    private d := new Dictionary<string, MRCDValue>;
    private make_on_item: MinimizableNode->ParsedFileItem->();
    
    public constructor(make_on_item: MinimizableNode->ParsedFileItem->()) := self.make_on_item := make_on_item;
    private constructor := raise new System.InvalidOperationException;
    
    public function Add(keywords: array of string; val: MRCDValue): MidReadCreationDict;
    begin
      foreach var kw in keywords do
        d.Add(kw.ToUpper, val);
      Result := self;
    end;
    public function Add(val: (array of string, MRCDValue)) := Add(val[0], val[1]);
    
    public function ValidateSection(section, text: StringSection): StringSection;
    begin
      Result := section;
      var all_mrcds := new Stack<MidReadCreationDict>(|self|);
      var all_keys_lazy := all_mrcds.SelectMany(mrcd->mrcd.d.Keys).Distinct;
      while true do
      begin
        text := text.WithI1(Result.I2);
        
        var found_stopper_kw := default(string);
        var found_stopper_range := default(SIndexRange);
        JTextBlock.ValidateNextStopper(text, all_keys_lazy, (kw, section, text)->
        begin
          Result := StringSection.Invalid;
          foreach var mrcd in all_mrcds do
          begin
            var val := default( MRCDValue );
            if mrcd.d.TryGetValue(kw, val) then
            begin
              Result := val.ValidateKW(section, text);
              if Result.IsInvalid then continue;
              while all_mrcds.Peek<>mrcd do all_mrcds.Pop;
              break;
            end;
          end;
        end, found_stopper_kw, found_stopper_range);
        
        if found_stopper_kw=nil then
        begin
          Result := Result.WithI2(text.I2);
          break;
        end;
        Result := Result.WithI2(found_stopper_range.i1);
        
        var curr_mrcd_val := all_mrcds.Peek.d[found_stopper_kw];
        if curr_mrcd_val.MakeNew=nil then break;
        Result := Result.WithI2(found_stopper_range.i2);
        
        var vampire := curr_mrcd_val.Vampire;
        if vampire<>nil then all_mrcds += vampire;
        
      end;
    end;
    
    //ToDo add_rest вообще надо?
    public function ReadSection(text: StringSection; f: ParsedPasFile; add_rest: boolean; on_item: ParsedFileItem->()): StringIndex;
    begin
      Result := text.I1;
      var left_text := default(ParsedFileItem);
      var all_mrcds := new Stack<(MidReadCreationDict,ParsedFileItem->())>(|(self, on_item)|);
      var all_keys_lazy := all_mrcds.SelectMany(t->t[0].d.Keys).Distinct;
      while true do
      begin
        var found_stopper_kw := default(string);
        var found_stopper_range := default(SIndexRange);
        var just_text := new JTextBlock(text, f, all_keys_lazy, (kw, section, text)->
        begin
          Result := StringSection.Invalid;
          foreach var (mrcd, on_item) in all_mrcds do
          begin
            on_item := on_item; //ToDo IDE#217
            var val := default( MRCDValue );
            if mrcd.d.TryGetValue(kw, val) then
            begin
              Result := val.ValidateKW(section, text);
              if Result.IsInvalid then continue;
              while all_mrcds.Peek[0]<>mrcd do all_mrcds.Pop;
              break;
            end;
          end;
        end, found_stopper_kw, found_stopper_range);
        case just_text.parts.EnmrDirect.Count of
          0: left_text := nil;
          1: left_text := just_text.parts.EnmrDirect.Single;
          else left_text := just_text;
        end;
        
        if found_stopper_kw=nil then break;
        Result := found_stopper_range.i1;
        var curr_mrcd_val := all_mrcds.Peek[0].d[found_stopper_kw];
        
        if curr_mrcd_val.MakeNew=nil then break;
        Result := found_stopper_range.i2;
        
        if left_text<>nil then all_mrcds.Peek[1]( left_text );
        var item := curr_mrcd_val.MakeNew(new StringSection(text.text, found_stopper_range), f);
        all_mrcds.Peek[1]( item );
        
        var vampire := curr_mrcd_val.Vampire;
        if vampire<>nil then all_mrcds += (vampire, vampire.make_on_item(item));
        
        text := text.WithI1(found_stopper_range.i2);
      end;
      if add_rest and (left_text<>nil) then on_item( left_text );
    end;
    public function ReadSection(text: StringSection; f: ParsedPasFile; add_rest: boolean; host: MinimizableNode) := ReadSection(text, f, add_rest, make_on_item(host));
    
  end;
  
  {$endregion MRCD}
  
  {$region PFList}
  
  {$region Base}
  
  PFListValue<TVal> = sealed class(ParsedFileItem)
  where TVal: ParsedFileItem;
    
    private space1: SpacingBlock;
    private val: TVal;
    private space2: MiscTextBlock;
    
    public constructor(need_space1: boolean; text: StringSection; f: ParsedPasFile; make_val: (StringSection, ParsedPasFile)->TVal);
    begin
      inherited Create(f, text.Length);
      
      self.space1 := if need_space1 then SpacingBlock.ReadStart(text, f) else nil;
      self.space2 := MiscTextBlock.ReadEndSpaces(text, f);
      self.val := make_val(text, f);
      
    end;
    
    protected function FileCleanupBody(is_invalid: MinimizableNode->boolean): StringIndex; override;
    begin
      Result := 0;
      if space1<>nil then
        Result += space1.FileCleanup(is_invalid);
      //ToDo #2507
      Result += (val as ParsedFileItem).FileCleanup(is_invalid);
      Result += ApplyFileCleanup(space2, is_invalid);
    end;
    protected procedure AddDirectChildrenTo(l: VulnerableNodeList); override;
    begin
      if space1<>nil then
        space1.AddDirectChildrenTo(l);
      if space2<>nil then l += space2;
    end;
    
    public procedure UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override;
    begin
      if space1<>nil then
        space1.UnWrapTo(tw, need_node);
      //ToDo #2507
      (val as ParsedFileItem).UnWrapTo(tw, need_node);
      if ApplyNeedNode(space2, need_node) then
        space2.UnWrapTo(tw, need_node);
    end;
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := 0;
      if space1<>nil then
        Result += space1.CountLines(need_node);
      //ToDo #2507
      Result += (val as ParsedFileItem).CountLines(need_node);
      if ApplyNeedNode(space2, need_node) then
        Result += space2.CountLines(need_node);
    end;
    
    protected procedure FillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override;
    begin
      if space1<>nil then
        space1.FillChangedSections(skipped, need_node, deleted, added);
      //ToDo #2507
      (val as ParsedFileItem).FillChangedSections(skipped, need_node, deleted, added);
      if space2<>nil then
        space2.FillChangedSections(skipped, need_node, deleted, added);
    end;
    protected procedure FillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); override;
    begin
      if (space1<>nil) and space1.FillIndexAreas(skipped, ind, l) then exit;
      //ToDo #2507
      if (val as ParsedFileItem).FillIndexAreas(skipped, ind, l) then exit;
      if (space2<>nil) and space2.FillIndexAreas(skipped, ind, l) then exit;
    end;
    
  end;
  
  PFList<T> = abstract class(ParsedFileItem)
  where T: ParsedFileItem;
    private pre_space: MiscTextBlock;
    private separator: string;
    private body := new MinimizableNodeList<PFListValue<T>>;
    
    protected function ValidateT(text: StringSection): StringSection; abstract;
    protected function MakeT(text: StringSection; f: ParsedPasFile): T; abstract;
    public constructor(text: StringSection; f: ParsedPasFile; separator: string := '');
    begin
      inherited Create(f, text.Length);
      if text.Length=0 then raise new System.InvalidOperationException(text.I1.ToString);
      self.separator := separator;
      
      pre_space := MiscTextBlock.ReadStartSpaces(text, f);
      while true do
      begin
        var section := text.WithI2(text.I1);
        var need_space1 := not body.IsEmpty;
        if need_space1 then
          section := section.NextWhile(text.I2, char.IsWhiteSpace);
        section.range.i2 := ValidateT(text.WithI1(section.I2)).I2;
        if not separator.All(char.IsWhiteSpace) then
          section := section.NextWhile(text.I2, char.IsWhiteSpace);
        body += new PFListValue<T>(need_space1, section, f, MakeT);
        text.range.i1 := section.I2;
        if text.Length=0 then break;
        if not text.StartsWith(separator) then raise new System.InvalidOperationException(text.ToString);
        text.range.i1 += separator.Length;
      end;
      
    end;
    
    public function EnmrDirect := body.EnmrDirect.Select(val->val.val);
    
    protected function FileCleanupBody(is_invalid: MinimizableNode->boolean): StringIndex; override;
    begin
      Result := FileListCleanup(body, is_invalid, separator.Length);
      if Result.IsInvalid then exit;
      if pre_space<>nil then
        Result += pre_space.FileCleanup(is_invalid);
    end;
    protected procedure AddDirectChildrenTo(l: VulnerableNodeList); override;
    begin
      if pre_space<>nil then l += pre_space;
      l += body;
    end;
    
    public procedure UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override;
    begin
      var needed_vals := body.EnmrDirect.Where(parent->ApplyNeedNode(parent, need_node)).ToList;
      if needed_vals.Count=0 then exit;
      if ApplyNeedNode(pre_space, need_node) then
        pre_space.UnWrapTo(tw, need_node);
      var non_first := false;
      foreach var val in needed_vals do
      begin
        if non_first then tw.Write(separator);
        non_first := true;
        val.UnWrapTo(tw, need_node);
      end;
    end;
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := 0;
      var needed_vals := body.EnmrDirect.Where(parent->ApplyNeedNode(parent, need_node)).ToList;
      if needed_vals.Count=0 then exit;
      if ApplyNeedNode(pre_space, need_node) then
        Result += pre_space.CountLines(need_node);
      foreach var val in needed_vals do
        Result += val.CountLines(need_node);
    end;
    
    protected procedure FillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override;
    begin
      if pre_space<>nil then
        pre_space.FillChangedSections(skipped, need_node, deleted, added);
      var non_first := false;
      foreach var val in body.EnmrDirect do
      begin
        if non_first then skipped += separator.Length;
        non_first := true;
        val.FillChangedSections(skipped, need_node, deleted, added);
      end;
    end;
    protected procedure FillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); override;
    begin
      if pre_space<>nil then
        if pre_space.FillIndexAreas(skipped, ind, l) then exit;
      var non_first := false;
      foreach var val in body.EnmrDirect do
      begin
        if non_first and AddIndexArea(skipped, ind, separator, l) then exit;
        non_first := true;
        if val.FillIndexAreas(skipped, ind, l) then exit;
      end;
    end;
    
  end;
  
  {$endregion Base}
  
  {$region Name}
  
  PFName = sealed class(ParsedFileItem)
    private name: MiscTextBlock;
    
    public static function ValidateStart(text: StringSection): StringSection;
    begin
      Result := text.TakeFirstWhile(CharIsNamePart);
      if Result.Length=0 then raise new System.InvalidOperationException(text.ToString);
    end;
    public constructor(text: StringSection; f: ParsedPasFile);
    begin
      inherited Create(f, text.Length);
      name := new MiscTextBlock(text, f, TT_Name);
    end;
    
    protected function FileCleanupBody(is_invalid: MinimizableNode->boolean): StringIndex; override := name.range.Length;
    protected procedure AddDirectChildrenTo(l: VulnerableNodeList); override := exit;
    
    public procedure UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override := name.UnWrapTo(tw, need_node);
    public function CountLines(need_node: MinimizableNode->boolean): integer; override := name.CountLines(need_node);
    
    protected procedure FillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override := exit;
    protected procedure FillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); override := exit;
    
  end;
  
  PFNameList = sealed class(PFList<PFName>)
    
    protected function ValidateT(text: StringSection): StringSection; override := PFName.ValidateStart(text);
    protected function MakeT(text: StringSection; f: ParsedPasFile): PFName; override := new PFName(text, f);
    
  end;
  
  {$endregion Name}
  
  {$region Type}
  
  PFTypeName = sealed partial class(ParsedFileItem)
    
    public static function ValidateStart(text: StringSection): StringSection;
    public constructor(text: StringSection; f: ParsedPasFile);
    
    public function FileCleanup(is_invalid: MinimizableNode->boolean): StringIndex; override;
    protected function FileCleanupBody(is_invalid: MinimizableNode->boolean): StringIndex; override;
    protected procedure AddDirectChildrenTo(l: VulnerableNodeList); override;
    
    public procedure UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override;
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    
    protected procedure FillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override;
    protected procedure FillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); override;
    
  end;
  
  PFTypeNameList = sealed class(PFList<PFTypeName>)
    
    protected function ValidateT(text: StringSection): StringSection; override :=
    PFTypeName.ValidateStart(text);
    
    protected function MakeT(text: StringSection; f: ParsedPasFile): PFTypeName; override :=
    new PFTypeName(text, f);
    
    public constructor(text: StringSection; f: ParsedPasFile) :=
    inherited Create(text, f, ',');
    
  end;
  
  TypeGenericToken = sealed class(MinimizableToken) end;
  TypeToken = sealed class(MinimizableToken)
    public generics := new List<TypeGenericToken>;
  end;
  
  {$endregion Type}
  
  {$endregion PFList}
  
  {$region Operator}
  
  PFOperatorBlock = sealed class(ParsedFileItem)
    
    private header: SIndexRange;
    private line_break1: SpacingBlock;
    private body := new MinimizableNodeList<ParsedFileItem>;
    private const end_string = 'end';
    private space1: MiscTextBlock;
    private end_closer: MiscTextBlock; private const allowed_end_closers = ';.';
    private line_break2: SpacingBlock;
    
    private static body_mrcd := MidReadCreationDict.Create(nil)
//      .Add(PFAnyOperator.mrcd_value)
    ;
    static constructor := body_mrcd
      .Add(PFOperatorBlock.mrcd_value)
      .Add(|end_string|, new MRCDValue(
        (section, text)->
        begin
          Result := StringSection.Invalid;
          
          var prev := section.Prev(text);
          if (prev<>nil) and not char.IsWhiteSpace(prev.Value) then exit;
          
          var last_i2 := section.I2;
          section := section.NextWhile(text.I2, char.IsWhiteSpace);
          var next := section.Next(text);
          if (next<>nil) and (next.Value in allowed_end_closers) then
          begin
            section.range.i2 += 1;
            section := section.NextWhile(text.I2, char.IsWhiteSpace);
          end;
          if section.I2 = last_i2 then exit;
          
          Result := section;
        end, nil, nil
      ))
    ;
    
    //ToDo Сделать обратный порядок параметров в конструкторах и MakeNew
    public constructor(text: StringSection; f: ParsedPasFile);
    begin
      inherited Create(f, text.Length);
      header := text.WithI2(text.I1).NextWhile(text.I2, CharIsNamePart, 1).range;
      text := text.WithI1(header.i2);
      
      line_break1 := SpacingBlock.ReadStart(text, f, #10);
      
      var ind := body_mrcd.ReadSection(text, f, true, body.Add);
      text := text.WithI1(ind);
      
      if not text.StartsWith(end_string) then raise new System.InvalidOperationException(text.ToString);
      text.range.i1 += end_string.Length;
      
      line_break2 := SpacingBlock.ReadEnd(text, f, #10);
      if allowed_end_closers.Any(ch->text.EndsWith(ch)) then
      begin
        end_closer := new MiscTextBlock(text.TakeLast(1), f, TT_Name);
        text.range.i2 -= 1;
      end;
      
      if text.Length<>0 then
        space1 := new MiscTextBlock(text, f, TT_WhiteSpace);
      
    end;
    
    public static keywords := |'begin', 'try', 'case', 'match'|;
    public static function ValidateKW(section, text: StringSection): StringSection;
    begin
      Result := StringSection.Invalid;
      
      var prev := section.Prev(text);
      if (prev<>nil) and not char.IsWhiteSpace(prev.Value) then exit;
      
      section := section.NextWhile(text.I2, char.IsWhiteSpace, 1);
      if section.IsInvalid then exit;
      
      section := body_mrcd.ValidateSection(section, text);
      if not text.WithI1(section.I2).StartsWith(end_string) then exit;
      section.range.i2 += end_string.Length;
      
      section := section.NextWhile(text.I2, char.IsWhiteSpace);
      var next := section.Next(text);
      if (next<>nil) and (next.Value in allowed_end_closers) then
      begin
        section.range.i2 += 1;
        section := section.NextWhile(text.I2, char.IsWhiteSpace);
      end;
      
      Result := section;
    end;
    public static function MakeNew(text: StringSection; f: ParsedPasFile): ParsedFileItem := new PFOperatorBlock(text, f);
    public static mrcd_value := (keywords, new MRCDValue(ValidateKW, MakeNew, nil));
    
    protected function FileCleanupBody(is_invalid: MinimizableNode->boolean): StringIndex; override;
    begin
      Result := header.Length;
      Result += line_break1.FileCleanup(is_invalid);
      Result += FileListCleanup(body, is_invalid);
      Result += end_string.Length;
      Result += ApplyFileCleanup(space1, is_invalid);
      Result += ApplyFileCleanup(end_closer, is_invalid);
      Result += line_break2.FileCleanup(is_invalid);
    end;
    protected procedure AddDirectChildrenTo(l: VulnerableNodeList); override;
    begin
      line_break1.AddDirectChildrenTo(l);
      l += body;
      if space1<>nil then l += space1;
      if end_closer<>nil then l += end_closer;
      line_break2.AddDirectChildrenTo(l);
    end;
    
    public procedure UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override;
    begin
      tw.Write(header.ToString(GetOriginalText));
      line_break1.UnWrapTo(tw, need_node);
      foreach var oper in body.EnmrDirect do
        if ApplyNeedNode(oper, need_node) then
          oper.UnWrapTo(tw, need_node);
      tw.Write(end_string);
      if ApplyNeedNode(space1, need_node) then
        space1.UnWrapTo(tw, need_node);
      if ApplyNeedNode(end_closer, need_node) then
        end_closer.UnWrapTo(tw, need_node);
      line_break2.UnWrapTo(tw, need_node);
    end;
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := 0;
      Result += line_break1.CountLines(need_node);
      foreach var oper in body.EnmrDirect do
        if ApplyNeedNode(oper, need_node) then
          Result += oper.CountLines(need_node);
      if ApplyNeedNode(space1, need_node) then
        Result += space1.CountLines(need_node);
      if ApplyNeedNode(end_closer, need_node) then
        Result += end_closer.CountLines(need_node);
      Result += line_break2.CountLines(need_node);
    end;
    
    protected procedure FillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override;
    begin
      skipped += header.Length;
      line_break1.FillChangedSections(skipped, need_node, deleted, added);
      foreach var oper in body.EnmrDirect do
        oper.FillChangedSections(skipped, need_node, deleted, added);
      skipped += end_string.Length;
      if space1<>nil then space1.FillChangedSections(skipped, need_node, deleted, added);
      if end_closer<>nil then end_closer.FillChangedSections(skipped, need_node, deleted, added);
      line_break2.FillChangedSections(skipped, need_node, deleted, added);
    end;
    protected procedure FillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); override;
    begin
      if AddIndexArea(skipped, ind, header, l) then exit;
      if line_break1.FillIndexAreas(skipped, ind, l) then exit;
      foreach var oper in body.EnmrDirect do
        if oper.FillIndexAreas(skipped, ind, l) then exit;
      if AddIndexArea(skipped, ind, end_string, l) then exit;
      if (space1<>nil) and space1.FillIndexAreas(skipped, ind, l) then exit;
      if (end_closer<>nil) and end_closer.FillIndexAreas(skipped, ind, l) then exit;
      if line_break2.FillIndexAreas(skipped, ind, l) then exit;
    end;
    
  end;
  
  {$endregion Operator}
  
  {$region Method}
  
//  PFMethod = sealed class(ParsedFileItem)
//    
//  end;
  
  {$endregion Method}
  
  {$region Type}
  
  PFAnyTypeDefinition = abstract partial class(ParsedFileItem)
    
    protected const separator = '=';
    
  end;
  PFTypeHeaderDefinition = sealed class(PFAnyTypeDefinition)
    
    private name: SIndexRange;
    private space1: SpacingBlock;
    // separator
    private space2: SpacingBlock;
    private body_type: SIndexRange;
    // ';'
    private line_break: SpacingBlock;
    
    public constructor(ind: StringIndex; text: StringSection; f: ParsedPasFile);
    begin
      inherited Create(f, text.Length);
      
      var name_section := text.TakeFirst(ind);
      text := text.TrimStart(ind+1);
      
      ind := name_section.IndexOf(char.IsWhiteSpace);
      if ind.IsInvalid then
      begin
        name := name_section.range;
        space1 := new SpacingBlock(name_section.TakeLast(0), f);
      end else
      begin
        name := name_section.TakeFirst(ind).range;
        space1 := new SpacingBlock(name_section.TrimStart(ind), f);
      end;
      
      space2 := SpacingBlock.ReadStart(text, f);
      
      ind := text.LastIndexOf(';');
      body_type := text.TakeFirst(ind).range;
      line_break := new SpacingBlock(text.TrimStart(ind+1), f, #10);
      
    end;
    
    protected function FileCleanupBody(is_invalid: MinimizableNode->boolean): StringIndex; override;
    begin
      Result := name.Length;
      Result += space1.FileCleanup(is_invalid);
      Result += 1; // separator
      Result += space2.FileCleanup(is_invalid);
      Result += body_type.Length;
      Result += 1; // ';'
      Result += line_break.FileCleanup(is_invalid);
    end;
    protected procedure AddDirectChildrenTo(l: VulnerableNodeList); override;
    begin
      space1.AddDirectChildrenTo(l);
      space2.AddDirectChildrenTo(l);
      line_break.AddDirectChildrenTo(l);
    end;
    
    public procedure UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override;
    begin
      tw.Write(name.ToString(GetOriginalText));
      space1.UnWrapTo(tw, need_node);
      tw.Write(separator);
      space2.UnWrapTo(tw, need_node);
      tw.Write(body_type.ToString(GetOriginalText));
      tw.Write(';');
      line_break.UnWrapTo(tw, need_node);
    end;
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := 0;
      Result += space1.CountLines(need_node);
      Result += space2.CountLines(need_node);
      Result += line_break.CountLines(need_node);
    end;
    
    protected procedure FillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override;
    begin
      skipped += name.Length;
      space1.FillChangedSections(skipped, need_node, deleted, added);
      skipped += 1; // separator
      space2.FillChangedSections(skipped, need_node, deleted, added);
      skipped += body_type.Length;
      skipped += 1; // ';'
      line_break.FillChangedSections(skipped, need_node, deleted, added);
    end;
    protected procedure FillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); override;
    begin
      if AddIndexArea(skipped, ind, name, l) then exit;
      if space1.FillIndexAreas(skipped, ind, l) then exit;
      if AddIndexArea(skipped, ind, separator, l) then exit;
      if space2.FillIndexAreas(skipped, ind, l) then exit;
      if AddIndexArea(skipped, ind, body_type, l) then exit;
      if AddIndexArea(skipped, ind, ';', l) then exit;
      if line_break.FillIndexAreas(skipped, ind, l) then exit;
    end;
    
  end;
  PFTypeBodyDefinition = sealed class(PFAnyTypeDefinition)
    public static keywords := |'class', 'record', 'interface'|;
    
    private name: SIndexRange;
    private space1: SpacingBlock;
    // separator
    private space2: SpacingBlock;
    private type_modifiers: PFNameList; // partial, sealed, etc.
    private space3: SpacingBlock; // only if type_modifiers<>nil
    private body_type: PFName; // class, record, etc.
    private space4: MiscTextBlock;
    // '('
    private parents: PFTypeNameList;
    // ')'
    private line_break1: SpacingBlock;
    private body := new MinimizableNodeList<ParsedFileItem>;
    private const end_string = 'end';
    private space5: MiscTextBlock;
    // ';'
    private line_break2: SpacingBlock;
    
    public static body_mrcd := MidReadCreationDict.Create(nil)
//      .Add(PFMethod.mrcd_value)
    ;
    static constructor :=
    body_mrcd.Add(|end_string|, new MRCDValue(
      (section, text)->
      begin
        Result := StringSection.Invalid;
        
        var prev := section.Prev(text);
        if (prev<>nil) and not char.IsWhiteSpace(prev.Value) then exit;
        
        var next := section.NextWhile(text.I2, char.IsWhiteSpace).Next(text);
        if (next=nil) or (next<>';') then exit;
        
        Result := section;
      end, nil, nil
    ));
    
    public constructor(ind: StringIndex; text: StringSection; f: ParsedPasFile);
    begin
      inherited Create(f, text.Length);
      
      var name_section := text.TakeFirst(ind);
      text := text.TrimStart(ind+1);
      
      ind := name_section.IndexOf(char.IsWhiteSpace);
      if ind.IsInvalid then
      begin
        name := name_section.range;
        space1 := new SpacingBlock(name_section.TakeLast(0), f);
      end else
      begin
        name := name_section.TakeFirst(ind).range;
        space1 := new SpacingBlock(name_section.TrimStart(ind), f);
      end;
      
      space2 := SpacingBlock.ReadStart(text, f);
      
      var body_type_section := text.SubSectionOfFirst(keywords);
      body_type := new PFName(body_type_section, f);
      
      var type_modifiers_section := text.WithI2(body_type_section.I1);
      if type_modifiers_section.Length<>0 then
      begin
        space3 := SpacingBlock.ReadEnd(type_modifiers_section, f);
        type_modifiers := new PFNameList(type_modifiers_section, f);
      end;
      
      text := text.WithI1(body_type_section.I2);
      if text.StartsWith('(') then
      begin
        text.range.i1 += 1;
        ind := text.IndexOf(')');
        parents := new PFTypeNameList(text.TakeFirst(ind), f);
        text.range.i1 += ind+1;
      end;
      
      line_break1 := SpacingBlock.ReadStart(text, f, #10);
      
      ind := body_mrcd.ReadSection(text, f, true, body.Add);
      text := text.WithI1(ind);
      
      if not text.StartsWith(end_string) then raise new System.InvalidOperationException(text.ToString);
      text.range.i1 += end_string.Length;
      
      space5 := MiscTextBlock.ReadStartSpaces(text, f);
      
      if not text.StartsWith(';') then raise new System.InvalidOperationException(text.ToString);
      text.range.i1 += 1;
      line_break2 := new SpacingBlock(text, f, #10);
      
    end;
    
    protected function FileCleanupBody(is_invalid: MinimizableNode->boolean): StringIndex; override;
    begin
      Result := name.Length;
      Result += space1.FileCleanup(is_invalid);
      Result += 1; // separator
      Result += space2.FileCleanup(is_invalid);
      Result += ApplyFileCleanup(type_modifiers, is_invalid);
      if type_modifiers<>nil then
        Result += space3.FileCleanup(is_invalid);
      Result += body_type.FileCleanup(is_invalid);
      Result += ApplyFileCleanup(space4, is_invalid);
      Result += ApplyFileCleanup(parents, is_invalid);
      if parents<>nil then
        Result += 2; // '()'
      Result += line_break1.FileCleanup(is_invalid);
      Result += FileListCleanup(body, is_invalid);
      Result += end_string.Length;
      Result += ApplyFileCleanup(space5, is_invalid);
      Result += 1; // ';'
      Result += line_break2.FileCleanup(is_invalid);
    end;
    protected procedure AddDirectChildrenTo(l: VulnerableNodeList); override;
    begin
      space1.AddDirectChildrenTo(l);
      space2.AddDirectChildrenTo(l);
      if type_modifiers<>nil then
      begin
        type_modifiers.AddDirectChildrenTo(l);
        space3.AddDirectChildrenTo(l);
      end;
      // body_type;
      if space4<>nil then space4.AddDirectChildrenTo(l);
      if parents<>nil then parents.AddDirectChildrenTo(l);
      line_break1.AddDirectChildrenTo(l);
      l += body;
      if space5<>nil then space5.AddDirectChildrenTo(l);
      line_break2.AddDirectChildrenTo(l);
    end;
    
    public procedure UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override;
    begin
      tw.Write(name.ToString(GetOriginalText));
      space1.UnWrapTo(tw, need_node);
      tw.Write(separator);
      space2.UnWrapTo(tw, need_node);
      if ApplyNeedNode(type_modifiers, need_node) then
      begin
        type_modifiers.UnWrapTo(tw, need_node);
        space3.UnWrapTo(tw, need_node);
      end;
      body_type.UnWrapTo(tw, need_node);
      if space4<>nil then
        space4.UnWrapTo(tw, need_node);
      if parents<>nil then
      begin
        tw.Write('(');
        parents.UnWrapTo(tw, need_node);
        tw.Write(')');
      end;
      line_break1.UnWrapTo(tw, need_node);
      foreach var cpi in body.EnmrDirect do
        if ApplyNeedNode(cpi, need_node) then
          cpi.UnWrapTo(tw, need_node);
      tw.Write(end_string);
      if ApplyNeedNode(space5, need_node) then space5.UnWrapTo(tw, need_node);
      tw.Write(';');
      line_break2.UnWrapTo(tw, need_node);
    end;
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := 0;
      Result += space1.CountLines(need_node);
      Result += space2.CountLines(need_node);
      if ApplyNeedNode(type_modifiers, need_node) then
      begin
        Result += type_modifiers.CountLines(need_node);
        Result += space3.CountLines(need_node);
      end;
      // body_type
      if ApplyNeedNode(space4, need_node) then
        Result += space4.CountLines(need_node);
      if ApplyNeedNode(parents, need_node) then
        Result += parents.CountLines(need_node);
      Result += line_break1.CountLines(need_node);
      foreach var cpi in body.EnmrDirect do
        if ApplyNeedNode(cpi, need_node) then
          Result += cpi.CountLines(need_node);
      if ApplyNeedNode(space5, need_node) then Result += space5.CountLines(need_node);
      Result += line_break2.CountLines(need_node);
    end;
    
    protected procedure FillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override;
    begin
      skipped += name.Length;
      space1.FillChangedSections(skipped, need_node, deleted, added);
      skipped += 1; // separator
      space2.FillChangedSections(skipped, need_node, deleted, added);
      if type_modifiers<>nil then
      begin
        type_modifiers.FillChangedSections(skipped, need_node, deleted, added);
        space3.FillChangedSections(skipped, need_node, deleted, added);
      end;
      body_type.FillChangedSections(skipped, need_node, deleted, added);
      if space4<>nil then
        space4.FillChangedSections(skipped, need_node, deleted, added);
      if parents<>nil then
      begin
        skipped += 1; // '('
        parents.FillChangedSections(skipped, need_node, deleted, added);
        skipped += 1; // ')'
      end;
      line_break1.FillChangedSections(skipped, need_node, deleted, added);
      foreach var cpi in body.EnmrDirect do
        cpi.FillChangedSections(skipped, need_node, deleted, added);
      skipped += end_string.Length;
      if space5<>nil then space5.FillChangedSections(skipped, need_node, deleted, added);
      skipped += 1; // ';'
      line_break2.FillChangedSections(skipped, need_node, deleted, added);
    end;
    protected procedure FillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); override;
    begin
      if AddIndexArea(skipped, ind, name, l) then exit;
      if space1.FillIndexAreas(skipped, ind, l) then exit;
      if AddIndexArea(skipped, ind, separator, l) then exit;
      if space2.FillIndexAreas(skipped, ind, l) then exit;
      if type_modifiers<>nil then
      begin
        if type_modifiers.FillIndexAreas(skipped, ind, l) then exit;
        if space3.FillIndexAreas(skipped, ind, l) then exit;
      end;
      if body_type.FillIndexAreas(skipped, ind, l) then exit;
      if (space4<>nil) and space4.FillIndexAreas(skipped, ind, l) then exit;
      if parents<>nil then
      begin
        if AddIndexArea(skipped, ind, '(', l) then exit;
        if parents.FillIndexAreas(skipped, ind, l) then exit;
        if AddIndexArea(skipped, ind, ')', l) then exit;
      end;
      if line_break1.FillIndexAreas(skipped, ind, l) then exit;
      foreach var cpi in body.EnmrDirect do
        if cpi.FillIndexAreas(skipped, ind, l) then exit;
      if AddIndexArea(skipped, ind, end_string, l) then exit;
      if (space5<>nil) and space5.FillIndexAreas(skipped, ind, l) then exit;
      if AddIndexArea(skipped, ind, ';', l) then exit;
      if line_break2.FillIndexAreas(skipped, ind, l) then exit;
    end;
    
  end;
  PFTypeSynonymDefinition = sealed class(PFAnyTypeDefinition)
    
    private new_name: SIndexRange;
    private space1: SpacingBlock;
    // separator
    private space2: SpacingBlock;
    private org_name: SIndexRange;
    // ';'
    private line_break: SpacingBlock;
    
    public constructor(ind: StringIndex; text: StringSection; f: ParsedPasFile);
    begin
      inherited Create(f, text.Length);
      
      var new_name_section := text.TakeFirst(ind);
      text := text.TrimStart(ind+1);
      
      ind := new_name_section.IndexOf(char.IsWhiteSpace);
      if ind.IsInvalid then
      begin
        new_name := new_name_section.range;
        space1 := new SpacingBlock(new_name_section.TakeLast(0), f);
      end else
      begin
        new_name := new_name_section.TakeFirst(ind).range;
        space1 := new SpacingBlock(new_name_section.TrimStart(ind), f);
      end;
      
      space2 := SpacingBlock.ReadStart(text, f);
      
      ind := text.LastIndexOf(';');
      org_name := text.TakeFirst(ind).range;
      line_break := new SpacingBlock(text.TrimStart(ind+1), f, #10);
      
    end;
    
    protected function FileCleanupBody(is_invalid: MinimizableNode->boolean): StringIndex; override;
    begin
      Result := new_name.Length;
      Result += space1.FileCleanup(is_invalid);
      Result += 1; // separator
      Result += space2.FileCleanup(is_invalid);
      Result += org_name.Length;
      Result += 1; // ';'
      Result += line_break.FileCleanup(is_invalid);
    end;
    protected procedure AddDirectChildrenTo(l: VulnerableNodeList); override;
    begin
      space1.AddDirectChildrenTo(l);
      space2.AddDirectChildrenTo(l);
      line_break.AddDirectChildrenTo(l);
    end;
    
    public procedure UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override;
    begin
      tw.Write(new_name.ToString(GetOriginalText));
      space1.UnWrapTo(tw, need_node);
      tw.Write(separator);
      space2.UnWrapTo(tw, need_node);
      tw.Write(org_name.ToString(GetOriginalText));
      tw.Write(';');
      line_break.UnWrapTo(tw, need_node);
    end;
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := 0;
      Result += space1.CountLines(need_node);
      Result += space2.CountLines(need_node);
      Result += line_break.CountLines(need_node);
    end;
    
    protected procedure FillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override;
    begin
      skipped += new_name.Length;
      space1.FillChangedSections(skipped, need_node, deleted, added);
      skipped += 1; // separator
      space2.FillChangedSections(skipped, need_node, deleted, added);
      skipped += org_name.Length;
      skipped += 1; // ';'
      line_break.FillChangedSections(skipped, need_node, deleted, added);
    end;
    protected procedure FillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); override;
    begin
      if AddIndexArea(skipped, ind, new_name, l) then exit;
      if space1.FillIndexAreas(skipped, ind, l) then exit;
      if AddIndexArea(skipped, ind, separator, l) then exit;
      if space2.FillIndexAreas(skipped, ind, l) then exit;
      if AddIndexArea(skipped, ind, org_name, l) then exit;
      if AddIndexArea(skipped, ind, ';', l) then exit;
      if line_break.FillIndexAreas(skipped, ind, l) then exit;
    end;
    
  end;
  PFTypeEnumDefinition = sealed class(PFAnyTypeDefinition)
    
    private name: SIndexRange;
    private space1: SpacingBlock;
    // separator
    private space2: SpacingBlock;
    // '('
    private enum_vals: PFNameList;
    // ')'
    private space3: MiscTextBlock;
    // ';'
    private line_break: SpacingBlock;
    
    public constructor(ind: StringIndex; text: StringSection; f: ParsedPasFile);
    begin
      inherited Create(f, text.Length);
      
      var name_section := text.TakeFirst(ind);
      text := text.TrimStart(ind+1);
      
      ind := name_section.IndexOf(char.IsWhiteSpace);
      if ind.IsInvalid then
      begin
        name := name_section.range;
        space1 := new SpacingBlock(name_section.TakeLast(0), f);
      end else
      begin
        name := name_section.TakeFirst(ind).range;
        space1 := new SpacingBlock(name_section.TrimStart(ind), f);
      end;
      
      space2 := SpacingBlock.ReadStart(text, f);
      
      if not text.StartsWith('(') then raise new System.InvalidOperationException;
      text.range.i1 += 1;
      
      ind := text.LastIndexOf(';');
      line_break := new SpacingBlock(text.TrimStart(ind+1), f, #10);
      text := text.TakeFirst(ind);
      
      ind := text.LastIndexOf(')');
      var space3_section := text.TrimStart(ind+1);
      space3 := if space3_section.Length=0 then nil else new MiscTextBlock(space3_section, f, TT_WhiteSpace);
      text := text.TakeFirst(ind);
      
      enum_vals := new PFNameList(text, f, ',');
      
    end;
    
    protected function FileCleanupBody(is_invalid: MinimizableNode->boolean): StringIndex; override;
    begin
      Result := StringIndex.Invalid;
      var vals_len := ApplyFileCleanup(enum_vals, is_invalid);
      if enum_vals=nil then exit;
      Result := name.Length;
      Result += space1.FileCleanup(is_invalid);
      Result += 1; // separator
      Result += space2.FileCleanup(is_invalid);
      Result += 1; // '('
      Result += vals_len;
      Result += 1; // ')'
      Result += ApplyFileCleanup(space3, is_invalid);
      Result += 1; // ';'
      Result += line_break.FileCleanup(is_invalid);
    end;
    protected procedure AddDirectChildrenTo(l: VulnerableNodeList); override;
    begin
      space1.AddDirectChildrenTo(l);
      space2.AddDirectChildrenTo(l);
      enum_vals.AddDirectChildrenTo(l);
      if space3<>nil then space3.AddDirectChildrenTo(l);
      line_break.AddDirectChildrenTo(l);
    end;
    
    public procedure UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override;
    begin
      tw.Write(name.ToString(GetOriginalText));
      space1.UnWrapTo(tw, need_node);
      tw.Write(separator);
      space2.UnWrapTo(tw, need_node);
      tw.Write('(');
      enum_vals.UnWrapTo(tw, need_node);
      tw.Write(')');
      if ApplyNeedNode(space3, need_node) then space3.UnWrapTo(tw, need_node);
      tw.Write(';');
      line_break.UnWrapTo(tw, need_node);
    end;
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := 0;
      Result += space1.CountLines(need_node);
      Result += space2.CountLines(need_node);
      Result += enum_vals.CountLines(need_node);
      if ApplyNeedNode(space3, need_node) then Result += space3.CountLines(need_node);
      Result += line_break.CountLines(need_node);
    end;
    
    protected procedure FillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override;
    begin
      skipped += name.Length;
      space1.FillChangedSections(skipped, need_node, deleted, added);
      skipped += 1; // separator
      space2.FillChangedSections(skipped, need_node, deleted, added);
      skipped += 1; // '('
      enum_vals.FillChangedSections(skipped, need_node, deleted, added);
      skipped += 1; // ')'
      if space3<>nil then space3.FillChangedSections(skipped, need_node, deleted, added);
      skipped += 1; // ';'
      line_break.FillChangedSections(skipped, need_node, deleted, added);
    end;
    protected procedure FillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); override;
    begin
      if AddIndexArea(skipped, ind, name, l) then exit;
      if space1.FillIndexAreas(skipped, ind, l) then exit;
      if AddIndexArea(skipped, ind, separator, l) then exit;
      if space2.FillIndexAreas(skipped, ind, l) then exit;
      if AddIndexArea(skipped, ind, '(', l) then exit;
      if enum_vals.FillIndexAreas(skipped, ind, l) then exit;
      if AddIndexArea(skipped, ind, ')', l) then exit;
      if (space3<>nil) and space3.FillIndexAreas(skipped, ind, l) then exit;
      if AddIndexArea(skipped, ind, ';', l) then exit;
      if line_break.FillIndexAreas(skipped, ind, l) then exit;
    end;
    
  end;
  PFAnyTypeDefinition = abstract partial class(ParsedFileItem)
    
    public static keywords := new string[](separator);
    
    private static function FindBodyTypeSection(text: StringSection): StringSection;
    begin
      Result := StringSection.Invalid;
      
      var res := text.SubSectionOfFirst(PFTypeBodyDefinition.keywords);
      if res.IsInvalid then exit;
      
      var next := res.Next(text);
      if (next=nil) or not char.IsWhiteSpace(next.Value) and not (next.Value = '(') then exit;
      
//      var t := text.WithI2(res.I1);
      if not text.WithI2(res.I1).All(ch->CharIsNamePart(ch) or char.IsWhiteSpace(ch)) then exit;
      
      Result := res;
    end;
    
    public static function ValidateKW(section, text: StringSection): StringSection;
    begin
      Result := StringSection.Invalid;
      
//      StringSection.Create(text.text)
//      .SubSectionOfFirst('PFTypeHeaderDefinition = sealed class(PFAnyTypeDefinition)')
//      .SubSectionOfFirst('=')
//      .I1.Println;
//      halt;
//      if section.I1 = 25266 then
//      begin
//        section := section;
//      end;
      
      section := section
        .PrevWhile(text.I1, char.IsWhiteSpace)
        .PrevWhile(text.I1, ch->CharIsNamePart(ch) or (ch in '<>'))
      ;
      
      var prev := section.Prev(text);
      if (prev<>nil) and not char.IsWhiteSpace(prev.Value) then exit;
      
      var body_type_section := FindBodyTypeSection(text.WithI1(section.I2));
      if body_type_section.IsInvalid then
      begin
        section := section.NextWhile(text.I2, char.IsWhiteSpace);
        var _section := section.WithI2(text.I2).TrimAfterFirst(';');
        if section.Next(text) = '(' then
        begin
          // ===== Enum =====
        end else
        begin
          // ===== Synonym =====
          if not _section.WithI1(section.I2).All(CharIsNamePart) then exit;
        end;
        section := _section;
      end else
      begin
        section := section.WithI2(body_type_section.I2).NextWhile(text.I2, char.IsWhiteSpace);
        
        var next := section.Next(text);
        if next = ';' then
        begin
          // ===== Header =====
          section.range.i2 += 1;
        end else
        begin
          // ===== Body =====
          
          if next = '(' then
          begin
            section.range.i2 += 1;
            var ind := text.WithI1(section.I2).IndexOf(')');
            if ind.IsInvalid then exit;
            if not StringSection.Create(text.text, section.I2, section.I2+ind).All(ch->char.IsWhiteSpace(ch) or (ch in '<>,') or CharIsNamePart(ch)) then exit;
            section.range.i2 += ind+1;
          end;
          
          section := PFTypeBodyDefinition.body_mrcd.ValidateSection(section, text);
          if text.WithI1(section.I2).StartsWith(PFTypeBodyDefinition.end_string) then
            section.range.i2 += PFTypeBodyDefinition.end_string.Length else
            exit;
          section := section.NextWhile(text.I2, char.IsWhiteSpace);
          
          // PFTypeBodyDefinition.body_mrcd shouldn't let this happen
          if section.Next(text) <> ';' then raise new System.InvalidOperationException;
          section.range.i2 += 1;
        end;
        
      end;
      
      Result := section.NextWhile(text.I2, char.IsWhiteSpace);
    end;
    public static function MakeNew(text: StringSection; f: ParsedPasFile): ParsedFileItem;
    begin
      var ind := text.IndexOf('=');
      var body_type_section := FindBodyTypeSection(text.TrimStart(ind+1));
      
      if body_type_section.IsInvalid then
      begin
        if text.TakeFirst(ind+1).NextWhile(text.I2, char.IsWhiteSpace).Next(text) = '(' then
          Result := new PFTypeEnumDefinition(ind, text, f) else
          Result := new PFTypeSynonymDefinition(ind, text, f);
      end else
      begin
        if text.WithI2(body_type_section.I2).NextWhile(text.I2, char.IsWhiteSpace).Next(text) = ';' then
          Result := new PFTypeHeaderDefinition(ind, text, f) else
          Result := new PFTypeBodyDefinition(ind, text, f);
      end;
      
    end;
    public static mrcd_value := (keywords, new MRCDValue(ValidateKW, MakeNew, nil));
    
  end;
  
  PFTypeSection = sealed class(ParsedFileItem)
    private const type_string = 'type';
    
    private line_break: SpacingBlock;
    private body := new MinimizableNodeList<ParsedFileItem>;
    private static function make_on_body_item(n: MinimizableNode): ParsedFileItem->();
    begin
      var host := PFTypeSection(n);
      Result := host.body.Add + host.IncLen;
    end;
    private static body_mrcd := MidReadCreationDict.Create(make_on_body_item)
      .Add(PFAnyTypeDefinition.mrcd_value)
    ;
    
    public constructor(text: StringSection; f: ParsedPasFile);
    begin
      inherited Create(f, text.Length);
      text := text.TrimStart(type_string.Length);
      line_break := new SpacingBlock(text, f, #10);
    end;
    
    public static keywords := |type_string|;
    public static function ValidateKW(section, text: StringSection): StringSection;
    begin
      Result := StringSection.Invalid;
      
      var prev := section.Prev(text);
      if (prev<>nil) and not char.IsWhiteSpace(prev.Value) then exit;
      
      section := section.NextWhile(text.I2, char.IsWhiteSpace, 1);
      if section.IsInvalid then exit;
      
      Result := section;
    end;
    public static function MakeNew(text: StringSection; f: ParsedPasFile): ParsedFileItem := new PFTypeSection(text, f);
    public static mrcd_value := (keywords, new MRCDValue(ValidateKW, MakeNew, body_mrcd));
    
    protected function FileCleanupBody(is_invalid: MinimizableNode->boolean): StringIndex; override;
    begin
      Result := type_string.Length;
      Result += line_break.FileCleanup(is_invalid);
      Result += FileListCleanup(body, is_invalid);
    end;
    protected procedure AddDirectChildrenTo(l: VulnerableNodeList); override;
    begin
      line_break.AddDirectChildrenTo(l);
      l += body;
    end;
    
    public procedure UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override;
    begin
      tw.Write(type_string);
      line_break.UnWrapTo(tw, need_node);
      foreach var pfi in body.EnmrDirect do
        if ApplyNeedNode(pfi, need_node) then
          pfi.UnWrapTo(tw, need_node);
    end;
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := line_break.CountLines(need_node);
      foreach var pfi in body.EnmrDirect do
        if ApplyNeedNode(pfi, need_node) then
          Result += pfi.CountLines(need_node);
    end;
    
    protected procedure FillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override;
    begin
      skipped += type_string.Length;
      line_break.FillChangedSections(skipped, need_node, deleted, added);
      foreach var pfi in body.EnmrDirect do
        pfi.FillChangedSections(skipped, need_node, deleted, added);
    end;
    protected procedure FillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); override;
    begin
      if AddIndexArea(skipped, ind, type_string, l) then exit;
      if line_break.FillIndexAreas(skipped, ind, l) then exit;
      foreach var pfi in body.EnmrDirect do
        if pfi.FillIndexAreas(skipped, ind, l) then
          exit;
    end;
    
  end;
  
  {$endregion Type}
  
  {$region FileSections}
  
  PFHeader = sealed class(ParsedFileItem)
    private kw: SIndexRange;
    
    private has_body: boolean;
    private space1: SpacingBlock;
    private body: SIndexRange;
    private line_break: SpacingBlock;
    
    public constructor(text: StringSection; f: ParsedPasFile);
    begin
      inherited Create(f, text.Length);
      
      var ind := text.IndexOf(char.IsWhiteSpace);
      if ind.IsInvalid then
      begin
        // ## Header
        kw := text.range;
        has_body := false;
      end else
      begin
        kw := text.TakeFirst(ind).range;
        text := text.TrimStart(ind);
        space1 := SpacingBlock.ReadStart(text, f);
        
        ind := text.LastIndexOf(';');
        line_break := new SpacingBlock(text.TrimStart(ind+1), f, #10);
        text := text.TakeFirst(ind);
        
        body := text.range;
        has_body := true;
      end;
      
    end;
    
    public static keywords := |'##', 'program', 'unit', 'library', 'namespace'|;
    public static function ValidateKW(section, text: StringSection): StringSection;
    begin
      Result := StringSection.Invalid;
      
      var prev := section.Prev(text);
      if (prev<>nil) and not char.IsWhiteSpace(prev.Value) then exit;
      
      if section = '##' then
      begin
        
        // ## => ###
        if section.Next(text) = '#' then section.range.i2 += 1;
        
        var next := section.Next(text);
        if (next<>nil) and not char.IsWhiteSpace(next.Value) then exit;
        
      end else
      begin
        
        var next := section.Next(text);
        if (next=nil) or not char.IsWhiteSpace(next.Value) then exit;
        
        section := section.WithI2(text.I2).TrimAfterFirst(';');
        if section.IsInvalid then exit;
        if section.Next(text) = #10 then section.range.i2 += 1;
        
      end;
      
      Result := section;
    end;
    public static function MakeNew(text: StringSection; f: ParsedPasFile): ParsedFileItem := new PFHeader(text, f);
    public static mrcd_value := (keywords, new MRCDValue(ValidateKW, MakeNew, nil));
    
    protected function FileCleanupBody(is_invalid: MinimizableNode->boolean): StringIndex; override;
    begin
      Result := kw.Length;
      if not has_body then exit;
      Result += space1.FileCleanup(is_invalid);
      Result += body.Length;
      Result += 1; // ';'
      Result += line_break.FileCleanup(is_invalid);
    end;
    protected procedure AddDirectChildrenTo(l: VulnerableNodeList); override :=
    space1.AddDirectChildrenTo(l);
    
    public procedure UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override;
    begin
      tw.Write(kw.ToString(GetOriginalText));
      if not has_body then exit;
      space1.UnWrapTo(tw, need_node);
      tw.Write(body.ToString(GetOriginalText));
      tw.Write(';');
      line_break.UnWrapTo(tw, need_node);
    end;
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := 0;
      if not has_body then exit;
      Result += space1.CountLines(need_node);
      Result += StringSection.Create(GetOriginalText, body).CountOf(#10);
      Result += line_break.CountLines(need_node);
    end;
    
    protected procedure FillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override;
    begin
      space1.FillChangedSections(skipped, need_node, deleted, added);
      line_break.FillChangedSections(skipped, need_node, deleted, added);
    end;
    protected procedure FillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); override;
    begin
      if not has_body then exit;
      if AddIndexArea(skipped, ind, kw, l) then exit;
      if space1.FillIndexAreas(skipped, ind, l) then exit;
      if AddIndexArea(skipped, ind, body, l) then exit;
      if line_break.FillIndexAreas(skipped, ind, l) then exit;
    end;
    
  end;
  
  PFUsedUnit = sealed class(ParsedFileItem)
    
    private space1: SpacingBlock;
    private name: SIndexRange;
    
    private has_in_path := false;
    private space2: SpacingBlock;
    private const in_separator = 'in';
    private space3: SpacingBlock;
    private in_path: SIndexRange;
    
    private space4: MiscTextBlock;
    
    public constructor(text: StringSection; f: ParsedPasFile);
    begin
      inherited Create(f, text.Length);
      
      self.space1 := SpacingBlock.ReadStart(text, f);
      self.space4 := MiscTextBlock.ReadEndSpaces(text, f);
      self.name := text.range;
      
      var ind := text.IndexOf(char.IsWhiteSpace);
      if ind.IsInvalid then exit;
      var name := text.TakeFirst(ind).range;
      text := text.TrimStart(ind);
      
      // Find "in"
      
      var space2 := SpacingBlock.ReadStart(text, f);
      if not text.StartsWith(in_separator) then exit;
      text := text.TrimStart(in_separator.Length);
      
      // Find path literal
      
      var space3 := SpacingBlock.ReadStart(text, f);
      var in_path := text.range;
      
      // Cleanup
      
      self.name := name;
      self.has_in_path := true;
      self.space2 := space2;
      self.space3 := space3;
      self.in_path := in_path;
      
    end;
    
    protected function FileCleanupBody(is_invalid: MinimizableNode->boolean): StringIndex; override;
    begin
      Result := 0;
      Result += space1.FileCleanup(is_invalid);
      Result += name.Length;
      if has_in_path then
      begin
        Result += space2.FileCleanup(is_invalid);
        Result += in_separator.Length;
        Result += space3.FileCleanup(is_invalid);
        Result += in_path.Length;
      end;
      Result += ApplyFileCleanup(space4, is_invalid);
    end;
    protected procedure AddDirectChildrenTo(l: VulnerableNodeList); override;
    begin
      space1.AddDirectChildrenTo(l);
      if has_in_path then
      begin
        space2.AddDirectChildrenTo(l);
        space3.AddDirectChildrenTo(l);
      end;
      if space4<>nil then l += space4;
    end;
    
    public procedure UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override;
    begin
      space1.UnWrapTo(tw, need_node);
      tw.Write(name.ToString(GetOriginalText));
      if has_in_path then
      begin
        space2.UnWrapTo(tw, need_node);
        tw.Write(in_separator);
        space3.UnWrapTo(tw, need_node);
        tw.Write(in_path.ToString(GetOriginalText));
      end;
      if ApplyNeedNode(space4, need_node) then
        space4.UnWrapTo(tw, need_node);
    end;
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := 0;
      Result += space1.CountLines(need_node);
      if has_in_path then
      begin
        Result += space2.CountLines(need_node);
        Result += space3.CountLines(need_node);
      end;
      if ApplyNeedNode(space4, need_node) then
        Result += space4.CountLines(need_node);
    end;
    
    protected procedure FillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override;
    begin
      space1.FillChangedSections(skipped, need_node, deleted, added);
      skipped += name.Length;
      if has_in_path then
      begin
        space2.FillChangedSections(skipped, need_node, deleted, added);
        skipped += in_separator.Length;
        space3.FillChangedSections(skipped, need_node, deleted, added);
        skipped += in_path.Length;
      end;
      if space4<>nil then
        space4.FillChangedSections(skipped, need_node, deleted, added);
    end;
    protected procedure FillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); override;
    begin
      if space1.FillIndexAreas(skipped, ind, l) then exit;
      if AddIndexArea(skipped, ind, name, l) then exit;
      if has_in_path then
      begin
        if space2.FillIndexAreas(skipped, ind, l) then exit;
        if AddIndexArea(skipped, ind, in_separator, l) then exit;
        if space3.FillIndexAreas(skipped, ind, l) then exit;
        if AddIndexArea(skipped, ind, in_path, l) then exit;
      end;
      if (space4<>nil) and space4.FillIndexAreas(skipped, ind, l) then exit;
    end;
    
  end;
  PFUsesSection = sealed class(ParsedFileItem)
    
    private const uses_string = 'uses';
    private used_units := new MinimizableNodeList<PFUsedUnit>;
    // ';'
    private line_break: SpacingBlock;
    
    public constructor(text: StringSection; f: ParsedPasFile);
    begin
      inherited Create(f, text.Length);
      text := text.TrimStart( uses_string.Length ); // 1 space left before unit name, same as after each ","
      
      begin
        var ind := text.LastIndexOf(';');
        line_break := new SpacingBlock(text.TrimStart(ind+1), f, #10);
        text := text.TakeFirst(ind);
      end;
      
      while true do
      begin
        var ind := text.IndexOf(',');
        if ind.IsInvalid then break;
        used_units += new PFUsedUnit(text.TakeFirst(ind), f);
        text := text.TrimStart(ind+1);
      end;
      used_units += new PFUsedUnit(text, f);
      
    end;
    
    public static keywords := |uses_string|;
    public static function ValidateKW(section, text: StringSection): StringSection;
    begin
      Result := StringSection.Invalid;
      
      var prev := section.Prev(text);
      if (prev<>nil) and not char.IsWhiteSpace(prev.Value) then exit;
      
      if section.Next(text) <> ' ' then exit;
      
      Result := section.WithI2(text.i2).TrimAfterFirst(';');
      if Result.Next(text) = #10 then Result.range.i2 += 1;
    end;
    public static function MakeNew(text: StringSection; f: ParsedPasFile): ParsedFileItem := new PFUsesSection(text, f);
    public static mrcd_value := (keywords, new MRCDValue(ValidateKW, MakeNew, nil));
    
    protected function FileCleanupBody(is_invalid: MinimizableNode->boolean): StringIndex; override;
    begin
      Result := StringIndex.Invalid;
      var units_len := FileListCleanup(used_units, is_invalid, 1);
      if used_units.IsEmpty then exit;
      Result := uses_string.Length;
      Result += units_len;
      Result += 1; // ';'
      Result += line_break.FileCleanup(is_invalid);
    end;
    protected procedure AddDirectChildrenTo(l: VulnerableNodeList); override;
    begin
      l += used_units;
      line_break.AddDirectChildrenTo(l);
    end;
    
    public procedure UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override;
    begin
      var units := used_units.EnmrDirect.ToList;
      units.RemoveAll(uu->not ApplyNeedNode(uu, need_node));
      if units.Count=0 then exit;
      
      tw.Write(uses_string);
      units[0].UnWrapTo(tw, need_node);
      for var i := 1 to units.Count-1 do
      begin
        tw.Write(',');
        units[i].UnWrapTo(tw, need_node);
      end;
      tw.Write(';');
      line_break.UnWrapTo(tw, need_node);
      
    end;
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := 0;
      var any_unit := false;
      foreach var uu in used_units.EnmrDirect do
        if ApplyNeedNode(uu, need_node) then
        begin
          Result += uu.CountLines(need_node);
          any_unit := true;
        end;
      if not any_unit then exit;
      Result += line_break.CountLines(need_node);
    end;
    
    protected procedure FillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override;
    begin
      skipped += uses_string.Length;
      var non_first_uu := false;
      foreach var uu in used_units.EnmrDirect do
      begin
        skipped += integer(non_first_uu); // ','
        uu.FillChangedSections(skipped, need_node, deleted, added);
        non_first_uu := true;
      end;
      line_break.FillChangedSections(skipped, need_node, deleted, added);
    end;
    protected procedure FillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); override;
    begin
      if AddIndexArea(skipped, ind, uses_string, l) then exit;
      var non_first_uu := false;
      foreach var uu in used_units.EnmrDirect do
      begin
        if non_first_uu and AddIndexArea(skipped, ind, ',', l) then exit;
        if uu.FillIndexAreas(skipped, ind, l) then exit;
        non_first_uu := true;
      end;
      if AddIndexArea(skipped, ind, ';', l) then exit;
      if line_break.FillIndexAreas(skipped, ind, l) then exit;
    end;
    
  end;
  
  PFUnitHalf = sealed class(ParsedFileItem)
    private kw: SIndexRange;
    
    private line_break: SpacingBlock;
    private body := new MinimizableNodeList<ParsedFileItem>;
    private static function make_on_body_item(n: MinimizableNode): ParsedFileItem->();
    begin
      var host := PFUnitHalf(n);
      Result := host.body.Add + host.IncLen;
    end;
    private static body_mrcd := MidReadCreationDict.Create(make_on_body_item)
      .Add(PFUsesSection.mrcd_value)
      .Add(PFTypeSection.mrcd_value)
      .Add(PFOperatorBlock.mrcd_value)
    ;
    
    public constructor(text: StringSection; f: ParsedPasFile);
    begin
      inherited Create(f, text.Length);
      
      var ind := text.IndexOf(char.IsWhiteSpace);
      kw := text.TakeFirst(ind).range;
      text := text.TrimStart(ind);
      
      line_break := new SpacingBlock(text, f, #10);
    end;
    
    public static keywords := |'interface', 'implementation'|;
    public static function ValidateKW(section, text: StringSection): StringSection;
    begin
      Result := StringSection.Invalid;
      
      var prev := section.Prev(text);
      if (prev<>nil) and not char.IsWhiteSpace(prev.Value) then exit;
      
      section := section.NextWhile(text.I2, char.IsWhiteSpace, 1);
      if section.IsInvalid then exit;
      
      Result := section;
    end;
    public static function MakeNew(text: StringSection; f: ParsedPasFile): ParsedFileItem := new PFUnitHalf(text, f);
    public static mrcd_value := (keywords, new MRCDValue(ValidateKW, MakeNew, body_mrcd));
    
    protected function FileCleanupBody(is_invalid: MinimizableNode->boolean): StringIndex; override;
    begin
      Result := kw.Length;
      Result += line_break.FileCleanup(is_invalid);
      Result += FileListCleanup(body, is_invalid);
    end;
    protected procedure AddDirectChildrenTo(l: VulnerableNodeList); override;
    begin
      line_break.AddDirectChildrenTo(l);
      l += body;
    end;
    
    public procedure UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override;
    begin
      tw.Write(kw.ToString(GetOriginalText));
      line_break.UnWrapTo(tw, need_node);
      foreach var pfi in body.EnmrDirect do
        if ApplyNeedNode(pfi, need_node) then
          pfi.UnWrapTo(tw, need_node);
    end;
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := line_break.CountLines(need_node);
      foreach var pfi in body.EnmrDirect do
        if ApplyNeedNode(pfi, need_node) then
          Result += pfi.CountLines(need_node);
    end;
    
    protected procedure FillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override;
    begin
      skipped += kw.Length;
      line_break.FillChangedSections(skipped, need_node, deleted, added);
      foreach var pfi in body.EnmrDirect do
        pfi.FillChangedSections(skipped, need_node, deleted, added);
    end;
    protected procedure FillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); override;
    begin
      if AddIndexArea(skipped, ind, kw, l) then exit;
      if line_break.FillIndexAreas(skipped, ind, l) then exit;
      foreach var pfi in body.EnmrDirect do
        if pfi.FillIndexAreas(skipped, ind, l) then
          exit;
    end;
    
  end;
  
  {$endregion FileSections}
  
{$region ParsedPasFile}

type
  ParsedPasFile = partial sealed class(ParsedFile)
    
    private body := new MinimizableNodeList<ParsedFileItem>;
    private static body_mrcd := MidReadCreationDict.Create(nil)
      .Add(PFHeader.mrcd_value)
      .Add(PFUnitHalf.mrcd_value)
      .Add(PFUsesSection.mrcd_value)
      .Add(PFTypeSection.mrcd_value)
      .Add(PFOperatorBlock.mrcd_value)
    ;
    
  end;
  
constructor ParsedPasFile.Create(fname, base_dir, target: string);
begin
  inherited Create(fname, base_dir, target);
  var text := new StringSection( self.original_text );
  
  body_mrcd.ReadSection(text, self, true, body.Add);
  
  //ToDo Костыль - надо из за вложенных вампиров (они добавляют длину себе, но не родителю)
  self.CleanupBody(n->false);
end;

procedure ParsedPasFile.CleanupBody(is_invalid: MinimizableNode->boolean);
begin
  tokens.Cleanup(is_invalid);
  ParsedFileItem.FileListCleanup(body, is_invalid);
end;
procedure ParsedPasFile.AddDirectChildrenTo(l: VulnerableNodeList);
begin
  tokens.AddDirectChildrenTo(l);
  l += body;
end;

procedure ParsedPasFile.UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean) :=
foreach var cpi in body.EnmrDirect do
  if ApplyNeedNode(cpi, need_node) then
    cpi.UnWrapTo(tw, need_node);

function ParsedPasFile.CountLines(need_node: MinimizableNode->boolean): integer;
begin
  Result := 1;
  
  foreach var cpi in body.EnmrDirect do
    if ApplyNeedNode(cpi, need_node) then
      Result += cpi.CountLines(need_node);
  
end;

procedure ParsedPasFile.FillChangedSectionsBody(need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>);
begin
  var skipped := 0;
  foreach var cpi in body.EnmrDirect do
    cpi.FillChangedSections(skipped, need_node, deleted, added);
end;

procedure ParsedPasFile.FillIndexAreasBody(ind: StringIndex; l: List<SIndexRange>);
begin
  var skipped := 0;
  foreach var cpi in body.EnmrDirect do
    if cpi.FillIndexAreas(skipped, ind, l) then
      break;
end;

{$endregion ParsedPasFile}

{$region PFTypeName}

type
  PFTypeName = sealed partial class(ParsedFileItem)
    
    private name: string; private token: TypeToken;
    // '<'
    private generics: PFTypeNameList;
    // '>'
    
  end;
  
static function PFTypeName.ValidateStart(text: StringSection): StringSection;
begin
  Result := text.TakeFirstWhile(CharIsNamePart);
  if Result.Length=0 then raise new System.InvalidOperationException(text.ToString);
  var with_space := Result.NextWhile(text.I2, char.IsWhiteSpace);
  if with_space.Next(text) = '<' then
  begin
    Result.range.i2 := with_space.I2;
    while true do
    begin
      Result.range.i2 += 1;
      Result := Result.NextWhile(text.I2, char.IsWhiteSpace);
      Result.range.i2 := PFTypeName.ValidateStart(text.WithI1(Result.I2)).I2;
      Result := Result.NextWhile(text.I2, char.IsWhiteSpace);
      var next := Result.Next(text);
      if next='>' then break;
      if next=',' then continue;
      raise new System.InvalidOperationException(text.ToString);
    end;
  end;
      
end;

constructor PFTypeName.Create(text: StringSection; f: ParsedPasFile);
begin
  inherited Create(f, text.Length);
  
  var name_section := text.TakeFirstWhile(CharIsNamePart);
  if name_section.Length=0 then raise new System.InvalidOperationException(text.ToString);
  text.range.i1 := name_section.I2;
  
  self.name := name_section.ToString;
  self.token := GetToken&<TypeToken>(name);
  self.token += self;
  
  if text.Length=0 then exit;
  if not text.StartsWith('<') or not text.EndsWith('>') then raise new System.InvalidOperationException(text.ToString);
  
  generics := new PFTypeNameList(text.TrimStart(1).TrimEnd(1), f);
  
  foreach var (i, generic) in generics.EnmrDirect.Numerate(0) do
  begin
    if i=token.generics.Count then token.generics += new TypeGenericToken;
    var gtoken := token.generics[i];
    gtoken += generic;
    generic.token += gtoken;
    self.token.generics.Add(gtoken);
  end;
  
end;

//ToDo Костыль - надо сохранять собственность токенов в ParsedFileItem
function PFTypeName.FileCleanup(is_invalid: MinimizableNode->boolean): StringIndex;
begin
  Result := inherited;
  if Result.IsInvalid then RemoveToken(self.name, self.token);
end;

function PFTypeName.FileCleanupBody(is_invalid: MinimizableNode->boolean): StringIndex;
begin
  Result := name.Length;
  Result += ApplyFileCleanup(generics, is_invalid);
  if generics=nil then
    token.generics := nil else
  begin
    Result += 2; // '<>'
    token.generics.RemoveAll(gtoken->is_invalid(gtoken));
  end;
end;

procedure PFTypeName.AddDirectChildrenTo(l: VulnerableNodeList);
begin
  l += self.token;
  foreach var gtoken in token.generics do
    l += gtoken; // instead of generics.AddDirectChildrenTo
end;

procedure PFTypeName.UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean);
begin
  tw.Write(name);
  if ApplyNeedNode(generics, need_node) then
  begin
    tw.Write('<');
    generics.UnWrapTo(tw, need_node);
    tw.Write('>');
  end;
end;

function PFTypeName.CountLines(need_node: MinimizableNode->boolean): integer;
begin
  Result := 0;
  if generics<>nil then
    generics.CountLines(need_node);
end;

procedure PFTypeName.FillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>);
begin
  skipped += name.Length;
  if generics<>nil then
  begin
    skipped += 1; // '<'
    generics.FillChangedSections(skipped, need_node, deleted, added);
    skipped += 1; // '>'
  end;
end;

procedure PFTypeName.FillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>);
begin
  if AddIndexArea(skipped, ind, name, l) then exit;
  if generics<>nil then
  begin
    if AddIndexArea(skipped, ind, '<', l) then exit;
    if generics.FillIndexAreas(skipped, ind, l) then exit;
    if AddIndexArea(skipped, ind, '>', l) then exit;
  end;
end;

{$endregion PFTypeName}

function ParseFile(fname, base_dir, target: string) := new ParsedPasFile(fname, base_dir, target);

begin
  ParsedFile.ParseByExt.Add('.pas', ParseFile);
end.