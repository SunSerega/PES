unit ParserCore;
{$string_nullbased+}

interface

uses PathUtils        in '..\..\..\Utils\PathUtils';

uses MinimizableCore  in '..\..\MinimizableCore';

type
  
  {$region Text Utils}
  
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
    public text: string := nil;
    public i1, i2: StringIndex; // [i1,i2)
    
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
    
    public static function operator in(ind: StringIndex; text: TextSection) := (ind>=text.i1) and (ind<=text.i2);
    
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
  
  {$endregion Text Utils}
  
  {$region Visualization Utils}
  
  PointAreasList = record
    private s: TextSection;
    private sub_areas := new List<PointAreasList>;
    
    public constructor(s: TextSection) := self.s := s;
    public constructor(s: TextSection; l: PointAreasList);
    begin
      self.s := s;
      self.sub_areas += l;
    end;
    private constructor := raise new System.InvalidOperationException;
    
    public property Section: TextSection read s;
    public property SubAreas: List<PointAreasList> read sub_areas;
    
  end;
  
  AddedText = record
    public ind: StringIndex;
    public descr: string;
    
    public constructor(ind: StringIndex; descr: string);
    begin
      self.ind := ind;
      self.descr := descr;
    end;
    
  end;
  
  {$endregion Visualization Utils}
  
  {$region ParsedFile}
  ParsedFile = class;
  
  ParsedFileItem = abstract class(MinimizableNode)
    public f: ParsedFile;
    public original_section: TextSection;
    
    public constructor(f: ParsedFile; original_section: TextSection);
    begin
      self.f := f;
      self.original_section := original_section;
    end;
    ///--
    public constructor := raise new System.InvalidOperationException;
    
    protected function get_original_text: string;
    
    public procedure UnWrapTo(sw: System.IO.StreamWriter; need_node: MinimizableNode->boolean); abstract;
    public function CountLines(need_node: MinimizableNode->boolean): integer; abstract;
    
    protected procedure FillBodyChangedSections(need_node: MinimizableNode->boolean; deleted: List<TextSection>; added: List<AddedText>); abstract;
    protected procedure FillBodyPointAreasList(ind: StringIndex; l: List<PointAreasList>); abstract;
    
    public procedure FillChangedSections(need_node: MinimizableNode->boolean; deleted: List<TextSection>; added: List<AddedText>);
    begin
      if not need_node(self) then
        deleted += original_section else
        FillBodyChangedSections(need_node, deleted, added);
    end;
    public function FillPointAreasList(ind: StringIndex; var l: PointAreasList): boolean;
    begin
      Result := ind in original_section;
      if not Result then exit;
      l := new PointAreasList(original_section);
      FillBodyPointAreasList(ind, l.SubAreas);
    end;
    
  end;
  
  ParsedFile = abstract class(MinimizableContainer)
    protected rel_fname: string;
    protected original_text: string;
    
    public static ParseByExt := new Dictionary<string, function(fname, base_dir, target:string): ParsedFile>;
    
    public constructor(fname, base_dir, target: string);
    begin
      self.rel_fname := GetRelativePath(fname, base_dir);
      self.original_text := ReadAllText(fname).Replace(#13#10,#10).Replace(#13,#10);
      self.invulnerable := rel_fname=target;
    end;
    ///--
    public constructor := raise new System.InvalidOperationException;
    
    public function ToString: string; override :=
    $'File[{rel_fname}]';
    
    protected procedure FillBodyChangedSections(need_node: MinimizableNode->boolean; deleted: List<TextSection>; added: List<AddedText>); abstract;
    protected procedure FillBodyPointAreasList(ind: StringIndex; l: List<PointAreasList>); abstract;
    
    /// (deleted, added)
    public function GetChangedSections(need_node: MinimizableNode->boolean): (List<TextSection>, List<AddedText>);
    begin
      var deleted := new List<TextSection>;
      var added := new List<AddedText>;
      FillBodyChangedSections(need_node, deleted, added);
      Result := (deleted, added);
    end;
    
    public function GetPointAreas(ind: StringIndex): PointAreasList;
    begin
      Result := new PointAreasList(new TextSection(original_text));
      FillBodyPointAreasList(ind, Result.SubAreas);
    end;
    
  end;
  
  {$endregion ParsedFile}
  
implementation

uses ParserPas;

function ParsedFileItem.get_original_text := f.original_text;

end.