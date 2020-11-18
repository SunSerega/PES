unit MinimizableCore;

interface

uses Counters;
uses ThreadUtils;

type
  
  {$region Node}
  
  MinimizableNode = abstract class
    
    public function Enmr: sequence of MinimizableNode;
    
    protected invulnerable: boolean;
    public property IsInvulnerable: boolean read invulnerable; virtual;
    
    public function Cleanup(is_invalid: MinimizableNode->boolean): MinimizableNode; virtual :=
    is_invalid(self) ? nil : self;
    
    public procedure UnWrapTo(new_base_dir: string; need_node: MinimizableNode->boolean); abstract;
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; abstract;
    
    public function ToString: string; override := $'Node[{self.GetType}]';
    
  end;
  
  MinimizableItem = abstract class(MinimizableNode)
    
  end;
  
  MinimizableList = abstract class(MinimizableNode)
    protected items := new List<MinimizableNode>;
    
    public function Cleanup(is_invalid: MinimizableNode->boolean): MinimizableNode; override;
    begin
      Result := nil;
      if is_invalid(self) then exit;
      Result := self;
      for var i := 0 to items.Count-1 do
        items[i] := items[i].Cleanup(is_invalid);
      items.RemoveAll(item->item=nil);
    end;
    
    public procedure UnWrapTo(new_base_dir: string; need_node: MinimizableNode->boolean := nil); override :=
    foreach var item in items do
      if (need_node=nil) or need_node(item) then
        item.UnWrapTo(new_base_dir, need_node);
    
    public function CountLines(need_node: MinimizableNode->boolean): integer; override;
    begin
      Result := 0;
      foreach var item in items do
        if (need_node=nil) or need_node(item) then
          Result += item.CountLines(need_node);
    end;
    
    public procedure Add(i: MinimizableNode);
    begin
      self.items += i;
      if i.IsInvulnerable then
        self.invulnerable := true;
    end;
    
  end;
  
  {$endregion Node}
  
  {$region Counter}
  
  InternalMinimizationContext = record
    public n: MinimizableNode;
    public removable_left: List<MinimizableNode>;
    public start_layer: integer;
    public base_path: string;
    public exec_test: string->boolean;
    public unique_names := new HashSet<string>;
    
    public function EnsureUniqueName(name: string): string;
    begin
      Result := name;
      lock unique_names do
        if unique_names.Add(Result) then
          exit;
      var i := 2;
      while true do
      begin
        Result := $'{name} ({i})';
        lock unique_names do
          if unique_names.Add(Result) then
            exit;
        i += 1;
      end;
    end;
    
    public function GetLayerForCount := (removable_left.Count div MaxThreadBatch).ClampBottom(1);
    
    public constructor(n: MinimizableNode; removable_left: List<MinimizableNode>; base_path: string; exec_test: string->boolean);
    begin
      self.n := n;
      self.removable_left := removable_left;
      self.start_layer := GetLayerForCount;
      self.base_path := base_path;
      self.exec_test := exec_test;
    end;
    
  end;
  
  MinimizationLayerCounter = sealed class(Counter)
    private c: InternalMinimizationContext;
    private layer: integer;
    
    public function Execute: boolean;
    
    protected event ReportLineCount: integer->();
    protected event NodeCountChanged: (integer, string)->();
    
    public property LayerRemoveCount: integer read layer;
    
    protected constructor(c: InternalMinimizationContext; layer: integer);
    begin
      self.c := c;
      self.layer := layer;
    end;
    private constructor := raise new System.InvalidOperationException;
    
  end;
  
  MinimizationCounter = sealed class(Counter)
    private c: InternalMinimizationContext;
    
    public function Execute: boolean;
    
    public event ReportLineCount: integer->();
    public event LayerAdded: MinimizationLayerCounter->();
    
    public constructor(n: MinimizableNode; base_path: string; exec_test: string->boolean);
    begin
      var removable_left := n.Enmr.Where(n->not n.IsInvulnerable).ToList;
      
      self.c := new InternalMinimizationContext(
        n,
        removable_left,
        base_path,
        exec_test
      );
      
    end;
    private constructor := raise new System.InvalidOperationException;
    
  end;
  
  {$endregion Counter}
  
implementation

uses ThreadUtils;

function MinimizableNode.Enmr: sequence of MinimizableNode;
begin
  yield self;
  var prev := new List<MinimizableList>;
  if self is MinimizableList(var l) then prev += l;
  
  while prev.Count<>0 do
  begin
    var curr := new List<MinimizableList>(prev.Count);
    
    foreach var l in prev do
      foreach var i in l.items do
      begin
        yield i;
        if i is MinimizableList(var sub_l) then
          curr += sub_l;
      end;
    
    prev := curr;
  end;
  
end;

/// l=кол-во элементов которые убирают
/// c=кол-во всех элементов
function EnmrRemInds(l, c: integer): sequence of array of integer;
begin
  if l<0 then raise new System.ArgumentException;
  
  if l*2 > c then
  begin
    foreach var inds in EnmrRemInds(c-l, c) do
    begin
      var res := new integer[l];
      var res_ind := 0;
      var inds_ind := 0;
      for var i := 0 to c-1 do
        if (inds_ind<>inds.Length) and (inds[inds_ind]=i) then
          inds_ind += 1 else
        begin
          res[res_ind] := i;
          res_ind += 1;
        end;
//      Writeln(inds);
//      Writeln(res);
//      Writeln('='*30);
      yield res;
    end;
    exit;
  end;
  
  case l of
    
    0:
    yield new integer[0];
    
    1:
    for var ind := 0 to c-1 do
      yield |ind|;
    
    else
    for var bl_size := l to c do
      foreach var insides in EnmrRemInds(l-2, bl_size-2) do
        for var shift := 0 to bl_size-1 do
          for var bl_ind := 0 to (c-shift) div bl_size - 1 do
          begin
            var bl_start := shift + bl_ind*bl_size;
            var res := new integer[l];
            res[0] := bl_start;
            res[l-1] := bl_start+bl_size-1;
            for var i := 0 to l-3 do
              res[i+1] := insides[i]+bl_start+1;
            yield res;
          end;
    
  end;
end;

function default_max_tests_before_giveup := MaxThreadBatch * 16;
const minimization_p = 2.2; // 1..∞

function MinimizationCounter.Execute: boolean;
begin
  Result := false;
  
  if c.removable_left.Count=0 then
  begin
    self.InvokeValueChanged(1);
    exit;
  end;
  
  var curr_layer := c.start_layer;
  
  var twice_nodes_left := c.removable_left.Count*2;
  var twice_initial_removable_count := twice_nodes_left;
  
  var l: MinimizationLayerCounter;
  while true do
  begin
    var InvokeValueChanged := self.InvokeValueChanged; //ToDo #2197
    
    if (l=nil) or (l.layer <> curr_layer) then
    begin
      l := new MinimizationLayerCounter(c, curr_layer);
      
      l.ReportLineCount += line_count->self.ReportLineCount(line_count);
      l.NodeCountChanged += (dnc, report_name)->
      begin
        twice_nodes_left += dnc;
//        if report_name<>nil then $'{report_name}: actual={c.removable_left.Count} progress={twice_nodes_left/2}'.Println;
        InvokeValueChanged(1 - twice_nodes_left/twice_initial_removable_count);
      end;
      
      var LayerAdded := LayerAdded;
      if LayerAdded<>nil then LayerAdded(l);
    end;
    
    if l.Execute then
      Result := true else
    if curr_layer>1 then
      curr_layer := curr_layer div 2 else
      break;
    
    curr_layer := curr_layer.ClampTop(c.GetLayerForCount);
  end;
  
end;

function MinimizationLayerCounter.Execute: boolean;
begin
  Result := false;
  InvokeValueChanged(0);
  
  var test_case_without := function(type_descr: string; without: HashSet<MinimizableNode>): boolean ->
  begin
    var unwrap_dir := System.IO.Path.Combine(c.base_path, c.EnsureUniqueName(type_descr));
    var unwraped_c := 0;
    
    var real_without := new List<MinimizableNode>(without.Count);
    
    c.n.UnWrapTo(unwrap_dir, n->
    begin
      Result := not without.Contains(n);
      if Result then
      begin
        if not n.IsInvulnerable then
          unwraped_c += 1;
      end else
      begin
        real_without += n;
      end;
    end);
    
    var sb := new StringBuilder;
    sb += type_descr;
    sb += ' - (';
    sb += c.removable_left.Count.ToString;
    sb += '-';
    sb += without.Count.ToString;
    sb += ' = ';
    sb += unwraped_c.ToString;
    sb += ') [';
    foreach var n in real_without do
      if sb.Length>=100 then
      begin
        sb += '..., ';
        break;
      end else
      begin
        sb += n.ToString;
        sb += ', ';
      end;
    if without.Count<>0 then sb.Length -= 2 else
      raise new System.InvalidOperationException;
    sb += ']';
    var curr_test_dir := System.IO.Path.Combine(c.base_path, c.EnsureUniqueName(sb.ToString));
    
    while true do
    try
      System.IO.Directory.Move(unwrap_dir, curr_test_dir);
      break;
    except
      on e: Exception do
      begin
        Writeln(unwrap_dir);
        Writeln(curr_test_dir);
        Writeln(e);
        continue;
      end;
    end;
    
    Result := c.exec_test(curr_test_dir);
  end;
  
  var max_tests_before_giveup := Round( c.removable_left.Count / ( self.layer ** (1/minimization_p) ) );
//  var max_tests_before_giveup := self.layer=1 ? c.removable_left.Count : Round(default_max_tests_before_giveup ** (
//    (LogN(default_max_tests_before_giveup, c.removable_left.Count)-1) *
//    ( (c.start_layer-layer)/(c.start_layer-1) ) ** minimization_p
//  +1));
  
  var cts := new System.Threading.CancellationTokenSource;
  var new_removed := new List<HashSet<MinimizableNode>>;
  var all_remove_set := new HashSet<MinimizableNode>;
  
  var since_stable := 0;
  var since_stable_lock := new object;
  
  var InvokeValueChanged := self.InvokeValueChanged; //ToDo #2197
  foreach var remove_set in ExecMany(
    EnmrRemInds(layer, c.removable_left.Count),
    inds->
    begin
      //ToDo #2345
      var f := function: HashSet<MinimizableNode> ->
      begin
        Result := nil;
        var curr_removed := new HashSet<MinimizableNode>(inds.Length);
        foreach var ind in inds do
          curr_removed += c.removable_left[ind];
        
        var any_removed: boolean;
        lock all_remove_set do
          any_removed := curr_removed.Any(n->not all_remove_set.Contains(n));
        
        if any_removed and test_case_without('test', curr_removed) then
        begin
          lock since_stable_lock do
          begin
            since_stable := 0;
            InvokeValueChanged(0);
          end;
          
          foreach var n in curr_removed.ToArray do
            foreach var sub_n in n.Enmr do
              curr_removed += sub_n;
          Result := curr_removed;
        end else
        lock since_stable_lock do
        begin
          since_stable += 1;
          InvokeValueChanged(since_stable.ClampTop(max_tests_before_giveup)/max_tests_before_giveup);
          if since_stable>=max_tests_before_giveup then
            cts.Cancel;
        end;
        
      end;
      Result := f;
    end,
    cts.Token
  ) do
  begin
    if remove_set=nil then continue;
    new_removed += remove_set;
    
    lock all_remove_set do
    begin
      var prev_count := all_remove_set.Count;
      all_remove_set.UnionWith(remove_set);
      self.NodeCountChanged(-(all_remove_set.Count - prev_count), nil);
      
      if not cts.IsCancellationRequested and (all_remove_set.Count >= c.removable_left.Count div 2) then
        cts.Cancel;
      
      self.ReportLineCount(c.n.CountLines(n->not all_remove_set.Contains(n)));
    end;
    
  end;
  
  if new_removed.Count=0 then exit;
  Result := true;
  
  //ToDo Изменение цвета во время unstable?
  if test_case_without('stable', all_remove_set) then
  begin
    c.n.Cleanup(n->n in all_remove_set);
    self.ReportLineCount(c.n.CountLines(nil));
    c.removable_left.RemoveAll(n->n in all_remove_set);
    self.NodeCountChanged(-all_remove_set.Count, 'Stable');
  end else
  begin
    self.NodeCountChanged(+all_remove_set.Count, 'Unstable start');
    
    foreach var remove_set in new_removed do
      if test_case_without('unstable', remove_set) then
      begin
        c.n.Cleanup(n->n in remove_set);
        self.ReportLineCount(c.n.CountLines(nil));
        
        var prev_count := c.removable_left.Count;
        c.removable_left.RemoveAll(n->n in remove_set);
        self.NodeCountChanged((prev_count-c.removable_left.Count) * -2, 'Unstable');
        
        all_remove_set.ExceptWith(remove_set);
      end;
    
  end;
  
//  self.InvokeValueChanged(1);
end;

end.