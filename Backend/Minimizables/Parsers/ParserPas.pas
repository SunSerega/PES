unit ParserPas;
{$string_nullbased+}

//ToDo Пройтись по всем ToDo

//ToDo Предупреждения
// - Хранить в ParsedFileItem, чтоб можно было показать визуально

interface

uses MinimizableCore  in '..\..\MinimizableCore';
uses ParserCore;

type
  
  ParsedPasFile = partial sealed class(ParsedFile)
    
    public constructor(fname, base_dir, target: string);
    
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override;
    protected procedure AddDirectBodyChildrenTo(l: List<MinimizableNode>); override;
    
    public procedure UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override;
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    
    protected procedure FillChangedSectionsBody(need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override;
    protected procedure FillIndexAreasBody(ind: StringIndex; l: List<SIndexRange>); override;
    
  end;
  
implementation

type
  
  {$region Text}
  
  MiscTextType = (MiscText, Comment, Directive);
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
         MiscText: if not text.IsWhiteSpace then ; //ToDo предупреждение
          Comment: ;
        Directive: ;
        else raise new System.InvalidOperationException(text_type.ToString);
      end;
      
    end;
    
    public function MakeStringSection := new StringSection(get_original_text, range);
    
    public static function ReadEndSpaces(var ptext: StringSection; f: ParsedPasFile): MiscTextBlock;
    begin
      var text := ptext;
      
      var ind := 0;
      var max_len := text.Length;
      while (ind<max_len) and char.IsWhiteSpace(text.TrimEnd(ind).Last) do
        ind += 1;
      if ind=0 then exit;
      
      ptext := text.TrimEnd(ind);
      Result := new MiscTextBlock(text.TakeLast(ind), f, MiscText);
    end;
    
    protected function FileCleanupBody(is_invalid: MinimizableNode->boolean): integer; override := range.Length;
    protected procedure AddDirectBodyChildrenTo(l: List<MinimizableNode>); override := exit;
    
    public procedure UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override := tw.Write( MakeStringSection.ToString );
    public function CountLines(need_node: MinimizableNode->boolean): integer; override := MakeStringSection.CountOf(#10);
    
    protected procedure FillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override := exit;
    protected procedure FillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); override := exit;
    
  end;
  
  MissingTextBlock = sealed class(MinimizableNode)
    private descr: string;
    public constructor(descr: string) := self.descr := descr;
    
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override := raise new System.InvalidOperationException;
    protected procedure AddDirectBodyChildrenTo(l: List<MinimizableNode>); override := exit;
    
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
            parts.Add(new MiscTextBlock(rest_text, f, MiscTextType.MiscText));
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
          self.parts.Add( new MiscTextBlock(new StringSection(text.text, unused_range), f, MiscTextType.MiscText) );
        
        // Apply found block
        if comment_end_dict.ContainsKey(kw) then
        begin
          parts.Add(new MiscTextBlock(expanded_section, f,
            if expanded_section.StartsWith(directive_start) then
              MiscTextType.Directive else
              MiscTextType.Comment
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
    
    protected function FileCleanupBody(is_invalid: MinimizableNode->boolean): integer; override := FileListCleanup(parts, is_invalid);
    protected procedure AddDirectBodyChildrenTo(l: List<MinimizableNode>); override := l += parts;
    
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
          extra_space := new MiscTextBlock(text, f, MiscTextType.MiscText);
      end;
      
    end;
    
    public static function ReadStart(var ptext: StringSection; f: ParsedPasFile; final_space: char := ' '): SpacingBlock;
    begin
      var text := ptext;
      
      var ind := 0;
      var max_len := text.Length;
      while (ind<max_len) and char.IsWhiteSpace(text[ind]) do
        ind += 1;
      ptext := text.TrimStart(ind);
      
      Result := new SpacingBlock(text.TakeFirst(ind), f, final_space);
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
    protected procedure AddDirectChildrenTo(l: List<MinimizableNode>);
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
      if extra_space<>nil then extra_space.FillChangedSections(skipped, need_node, deleted, added);
      if missing_space<>nil then missing_space.FillChangedSections(skipped, need_node, added);
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
  
  {$region Common}
  
  CommonParsedItem = abstract class(ParsedFileItem)
    protected pretext: JTextBlock;
    
    public constructor(pretext: JTextBlock; len: StringIndex; f: ParsedPasFile);
    begin
      inherited Create(f, (if pretext=nil then 0 else pretext.len)+len);
      self.pretext := pretext;
    end;
    private constructor := raise new System.InvalidOperationException;
    
    protected function CommonFileCleanupBody(is_invalid: MinimizableNode->boolean): integer; abstract;
    protected procedure CommonAddDirectChildrenTo(l: List<MinimizableNode>); abstract;
    
    public procedure CommonUnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); abstract;
    public function CommonCountLines(need_node: MinimizableNode->boolean): integer; abstract;
    
    protected procedure CommonFillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); abstract;
    protected procedure CommonFillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); abstract;
    
    protected function FileCleanupBody(is_invalid: MinimizableNode->boolean): integer; override;
    begin
      Result := 0;
      if pretext<>nil then
      begin
        var len := pretext.FileCleanup(is_invalid);
        if len.IsInvalid then
          pretext := nil else
          Result += len;
      end;
      Result += CommonFileCleanupBody(is_invalid);
    end;
    
    protected procedure AddDirectBodyChildrenTo(l: List<MinimizableNode>); override;
    begin
      if pretext<>nil then l += pretext;
      CommonAddDirectChildrenTo(l);
    end;
    
    public procedure UnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override;
    begin
      if ApplyNeedNode(pretext, need_node) then pretext.UnWrapTo(tw, need_node);
      CommonUnWrapTo(tw, need_node);
    end;
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result += 0;
      if ApplyNeedNode(pretext, need_node) then
        Result += pretext.CountLines(need_node);
      Result += CommonCountLines(need_node);
    end;
    
    protected procedure FillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override;
    begin
      if pretext<>nil then pretext.FillChangedSections(skipped, need_node, deleted, added);
      CommonFillChangedSectionsBody(skipped, need_node, deleted, added);
    end;
    protected procedure FillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); override;
    begin
//      Println(skipped, ind, len);
      var own_area_ind := l.Count-1;
      if pretext<>nil then
      begin
        if pretext.FillIndexAreas(skipped, ind, l) then
        begin
          l.RemoveAt(own_area_ind); // delete own area - self doesn't really contain pretext
          exit;
        end else
        begin
          var area := l[own_area_ind];
          area.i1 += pretext.len;
          l[own_area_ind] := area;
        end;
      end;
//      Println(skipped, ind, len);
      CommonFillIndexAreasBody(skipped, ind, l);
//      Println(skipped, ind, len);
    end;
    
  end;
  
  EmptyCommonParsedItem = sealed class(CommonParsedItem)
    
    public constructor(pretext: JTextBlock; f: ParsedPasFile) :=
    inherited Create(pretext, 0, f);
    
    protected function CommonFileCleanupBody(is_invalid: MinimizableNode->boolean): integer; override := 0;
    protected procedure CommonAddDirectChildrenTo(l: List<MinimizableNode>); override := exit;
    
    public procedure CommonUnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override := exit;
    public function CommonCountLines(need_node: MinimizableNode->boolean): integer; override := 0;
    
    protected procedure CommonFillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override := exit;
    protected procedure CommonFillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); override := exit;
    
  end;
  
  {$endregion Common}
  
  {$region MRCD}
  
  MRCDValue = sealed auto class
    public ValidateKW: function(section, whole_text: StringSection): StringSection;
    public MakeNew: function(pretext: JTextBlock; text: StringSection; f: ParsedPasFile): CommonParsedItem;
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
    
    private function ValidateStopper(kw: string; section, text: StringSection) := d[kw].ValidateKW(section, text);
    
    public function ValidateSection(section, text: StringSection): StringSection;
    begin
      Result := section;
      while true do
      begin
        text := text.WithI1(Result.I2);
        
        var found_stopper_kw := default(string);
        var found_stopper_range := default(SIndexRange);
        JTextBlock.ValidateNextStopper(text, d.Keys, ValidateStopper, found_stopper_kw, found_stopper_range);
        
        if found_stopper_kw=nil then
        begin
          Result := Result.WithI2(text.I2);
          break;
        end;
        Result := Result.WithI2(found_stopper_range.i1);
        
        if d[found_stopper_kw].MakeNew=nil then break;
        Result := Result.WithI2(found_stopper_range.i2);
      end;
    end;
    
    public procedure ReadSection(text: StringSection; f: ParsedPasFile; on_item: CommonParsedItem->());
    begin
      var just_text := default(JTextBlock);
      while true do
      begin
        var found_stopper_kw := default(string);
        var found_stopper_range := default(SIndexRange);
        just_text := new JTextBlock(text, f, d.Keys, ValidateStopper, found_stopper_kw, found_stopper_range);
        if just_text.parts.IsEmpty then just_text := nil;
        
        if found_stopper_kw=nil then break;
        
        var MakeNew := d[found_stopper_kw].MakeNew;
        //ToDo #2503
        var item := MakeNew=nil?nil:MakeNew.Invoke(just_text, new StringSection(text.text, found_stopper_range), f);
        if item=nil then
          break else
          on_item( item );
        
        text := text.WithI1(found_stopper_range.i2);
      end;
      if just_text<>nil then
        on_item( new EmptyCommonParsedItem(just_text, f) );
    end;
    
  end;
  
  {$endregion MRCD}
  
  {$region Operator}
  
  {$endregion Operator}
  
  {$region Method}
  
  {$endregion Method}
  
  {$region Type}
  
//  PFTypeSection = sealed class(ParsedFileItem)
//    
//  end;
  
  {$endregion Type}
  
  {$region FileSections}
  
  PFHeader = sealed class(CommonParsedItem)
    private kw: SIndexRange;
    
    private has_body: boolean;
    private space1: SpacingBlock;
    private body: SIndexRange;
    private line_break: SpacingBlock;
    
    public constructor(pretext: JTextBlock; text: StringSection; f: ParsedPasFile);
    begin
      inherited Create(pretext, text.Length, f);
      
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
    public static function MakeNew(pretext: JTextBlock; text: StringSection; f: ParsedPasFile): CommonParsedItem := new PFHeader(pretext, text, f);
    public static mrcd_value := (keywords, new MRCDValue(ValidateKW, MakeNew));
    
    protected function CommonFileCleanupBody(is_invalid: MinimizableNode->boolean): integer; override;
    begin
      Result := kw.Length;
      if not has_body then exit;
      Result += space1.FileCleanup(is_invalid);
      Result += body.Length;
      Result += 1; // ';'
      Result += line_break.FileCleanup(is_invalid);
    end;
    protected procedure CommonAddDirectChildrenTo(l: List<MinimizableNode>); override :=
    space1.AddDirectChildrenTo(l);
    
    public procedure CommonUnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override;
    begin
      tw.Write(kw.ToString(get_original_text));
      if not has_body then exit;
      space1.UnWrapTo(tw, need_node);
      tw.Write(body.ToString(get_original_text));
      tw.Write(';');
      line_break.UnWrapTo(tw, need_node);
    end;
    
    public function CommonCountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := 0;
      if not has_body then exit;
      Result += space1.CountLines(need_node);
      Result += StringSection.Create(get_original_text, body).CountOf(#10);
      Result += line_break.CountLines(need_node);
    end;
    
    protected procedure CommonFillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override;
    begin
      space1.FillChangedSections(skipped, need_node, deleted, added);
      line_break.FillChangedSections(skipped, need_node, deleted, added);
    end;
    protected procedure CommonFillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); override;
    begin
      if not has_body then exit;
      if AddIndexArea(skipped, ind, kw, l) then exit;
      if space1.FillIndexAreas(skipped, ind, l) then exit;
      if AddIndexArea(skipped, ind, body, l) then exit;
      if line_break.FillIndexAreas(skipped, ind, l) then exit;
    end;
    
  end;
  
  PFUnitHalf = sealed class(CommonParsedItem)
    private kw: SIndexRange;
    
    private line_break: SpacingBlock;
    private body := new MinimizableNodeList<CommonParsedItem>;
    private static body_mrcd := MidReadCreationDict.Create;
    static constructor;
    begin
      body_mrcd
//        .Add(PFTypeSection.mrcd_value)
        .Add(keywords+|'begin', 'end.'|, new MRCDValue(
          (section, text)->
          begin
            Result := StringSection.Invalid;
            
            var prev := section.Prev(text);
            if (prev<>nil) and not char.IsWhiteSpace(prev.Value) then exit;
            
            if not section.EndsWith('.') then
            begin
              var next := section.Next(text);
              if (next=nil) or not char.IsWhiteSpace(next.Value) then exit;
            end;
            
            Result := section.WithI2(text.I2);
          end,
          nil
        ))
      ;
    end;
    
    public constructor(pretext: JTextBlock; text: StringSection; f: ParsedPasFile);
    begin
      inherited Create(pretext, text.Length, f);
      
      var ind := text.IndexOf(char.IsWhiteSpace);
      kw := text.TakeFirst(ind).range;
      text := text.TrimStart(ind);
      
      line_break := SpacingBlock.ReadStart(text, f, #10);
      
      body_mrcd.ReadSection(text, f, self.body.Add);
      
    end;
    
    public static keywords := |'interface', 'implementation'|;
    public static function ValidateKW(section, text: StringSection): StringSection;
    begin
      Result := StringSection.Invalid;
      
      var prev := section.Prev(text);
      if (prev<>nil) and not char.IsWhiteSpace(prev.Value) then exit;
      
      var next := section.Next(text);
      if (next=nil) or not char.IsWhiteSpace(next.Value) then exit;
      section.range.i2 += 1;
      
      Result := body_mrcd.ValidateSection(section, text.WithI1(section.I2));
    end;
    public static function MakeNew(pretext: JTextBlock; text: StringSection; f: ParsedPasFile): CommonParsedItem := new PFUnitHalf(pretext, text, f);
    public static mrcd_value := (keywords, new MRCDValue(ValidateKW, MakeNew));
    
    protected function CommonFileCleanupBody(is_invalid: MinimizableNode->boolean): integer; override;
    begin
      Result := kw.Length;
      Result += line_break.FileCleanup(is_invalid);
      Result += FileListCleanup(body, is_invalid);
    end;
    protected procedure CommonAddDirectChildrenTo(l: List<MinimizableNode>); override;
    begin
      line_break.AddDirectChildrenTo(l);
      l += body;
    end;
    
    public procedure CommonUnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override;
    begin
      tw.Write(kw.ToString(get_original_text));
      line_break.UnWrapTo(tw, need_node);
      foreach var pfi in body.EnmrDirect do
        if ApplyNeedNode(pfi, need_node) then
          pfi.UnWrapTo(tw, need_node);
    end;
    
    public function CommonCountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := line_break.CountLines(need_node);
      foreach var pfi in body.EnmrDirect do
        if ApplyNeedNode(pfi, need_node) then
          Result += pfi.CountLines(need_node);
    end;
    
    protected procedure CommonFillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override;
    begin
      skipped += kw.Length;
      line_break.FillChangedSections(skipped, need_node, deleted, added);
      foreach var pfi in body.EnmrDirect do
        pfi.FillChangedSections(skipped, need_node, deleted, added);
    end;
    protected procedure CommonFillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); override;
    begin
      if AddIndexArea(skipped, ind, kw, l) then exit;
      if line_break.FillIndexAreas(skipped, ind, l) then exit;
      foreach var pfi in body.EnmrDirect do
        if pfi.FillIndexAreas(skipped, ind, l) then
          exit;
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
    
    protected function FileCleanupBody(is_invalid: MinimizableNode->boolean): integer; override;
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
      if space4<>nil then
      begin
        var len := space4.FileCleanup(is_invalid);
        if len.IsInvalid then
          space4 := nil else
          Result += len;
      end;
    end;
    protected procedure AddDirectBodyChildrenTo(l: List<MinimizableNode>); override;
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
      tw.Write(name.ToString(get_original_text));
      if has_in_path then
      begin
        space2.UnWrapTo(tw, need_node);
        tw.Write(in_separator);
        space3.UnWrapTo(tw, need_node);
        tw.Write(in_path.ToString(get_original_text));
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
  PFUsesSection = sealed class(CommonParsedItem)
    
    private const uses_string = 'uses';
    private used_units := new MinimizableNodeList<PFUsedUnit>;
    private line_break: SpacingBlock;
    
    public constructor(pretext: JTextBlock; text: StringSection; f: ParsedPasFile);
    begin
      inherited Create(pretext, text.Length, f);
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
    public static function MakeNew(pretext: JTextBlock; text: StringSection; f: ParsedPasFile): CommonParsedItem := new PFUsesSection(pretext, text, f);
    public static mrcd_value := (keywords, new MRCDValue(ValidateKW, MakeNew));
    
    protected function CommonFileCleanupBody(is_invalid: MinimizableNode->boolean): integer; override;
    begin
      Result := uses_string.Length;
      Result += FileListCleanup(used_units, is_invalid);
      Result += 1; // ';'
      Result += line_break.FileCleanup(is_invalid);
    end;
    protected procedure CommonAddDirectChildrenTo(l: List<MinimizableNode>); override;
    begin
      l += used_units;
      line_break.AddDirectChildrenTo(l);
    end;
    
    public procedure CommonUnWrapTo(tw: System.IO.TextWriter; need_node: MinimizableNode->boolean); override;
    begin
      tw.Write(uses_string);
      foreach var uu in used_units.EnmrDirect do
        if ApplyNeedNode(uu, need_node) then
          uu.UnWrapTo(tw, need_node);
      tw.Write(';');
      line_break.UnWrapTo(tw, need_node);
    end;
    
    public function CommonCountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := 0;
      foreach var uu in used_units.EnmrDirect do
        if ApplyNeedNode(uu, need_node) then
          Result += uu.CountLines(need_node);
      Result += line_break.CountLines(need_node);
    end;
    
    protected procedure CommonFillChangedSectionsBody(var skipped: integer; need_node: MinimizableNode->boolean; deleted: List<SIndexRange>; added: List<AddedText>); override;
    begin
      skipped += uses_string.Length;
      foreach var uu in used_units.EnmrDirect do
        uu.FillChangedSections(skipped, need_node, deleted, added);
      line_break.FillChangedSections(skipped, need_node, deleted, added);
    end;
    protected procedure CommonFillIndexAreasBody(var skipped: integer; ind: StringIndex; l: List<SIndexRange>); override;
    begin
      if AddIndexArea(skipped, ind, uses_string, l) then exit;
      foreach var uu in used_units.EnmrDirect do
        if uu.FillIndexAreas(skipped, ind, l) then
          exit;
      if line_break.FillIndexAreas(skipped, ind, l) then exit;
    end;
    
  end;
  
  {$endregion FileSections}
  
{$region ParsedPasFile}

type
  ParsedPasFile = partial sealed class(ParsedFile)
    
    private body := new MinimizableNodeList<CommonParsedItem>;
    private static whole_file_mrcd := MidReadCreationDict.Create
      .Add(PFHeader.mrcd_value)
      .Add(PFUnitHalf.mrcd_value)
      .Add(PFUsesSection.mrcd_value)
//      .Add(PFTypeSection.mrcd_value)
    ;
    
  end;
  
constructor ParsedPasFile.Create(fname, base_dir, target: string);
begin
  inherited Create(fname, base_dir, target);
  var text := new StringSection( self.original_text );
  
  whole_file_mrcd.ReadSection(text, self, self.body.Add);
  
end;

procedure ParsedPasFile.CleanupBody(is_invalid: MinimizableNode->boolean) := ParsedFileItem.FileListCleanup(body, is_invalid);
procedure ParsedPasFile.AddDirectBodyChildrenTo(l: List<MinimizableNode>) := l += body;

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

function ParseFile(fname, base_dir, target: string) := new ParsedPasFile(fname, base_dir, target);

begin
  ParsedFile.ParseByExt.Add('.pas', ParseFile);
end.