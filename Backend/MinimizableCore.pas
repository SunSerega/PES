unit MinimizableCore;
{$savepcu false} //ToDo #2346

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
//uses AQueue in '..\Utils\AQueue';

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

type
  LocalTestT = function(type_descr: string; without: HashSet<MinimizableNode>; new_removed_count: integer?): boolean;
  
  RemovalTree = sealed class
    private AllNodes := new HashSet<MinimizableNode>;
    private Branches := new List<RemovalTree>;
    
    public constructor(l: List<HashSet<MinimizableNode>>);
    begin
      var MaxThreadBatch := ThreadUtils.MaxThreadBatch;
      
      if l.Count > MaxThreadBatch then
      begin
        var m: integer;
        var d := System.Math.DivRem(l.Count, MaxThreadBatch, m);
        var last_ind := 0;
        
        for var i_branch := 0 to MaxThreadBatch-1 do
        begin
          var c := d + integer(i_branch < m);
          var t := new RemovalTree(l.GetRange(last_ind, c));
          foreach var n in t.AllNodes do
            self.AllNodes += n;
          self.Branches += t;
          last_ind += c;
        end;
        
        {$ifdef DEBUG}
        if last_ind<>l.Count then
          raise new System.InvalidOperationException;
        {$endif DEBUG}
        
      end else
      if l.Count=1 then
        self.AllNodes := l.Single else
        foreach var hs in l do
        begin
          var branch := new RemovalTree;
          branch.AllNodes := hs;
          self.AllNodes.UnionWith(hs);
          self.Branches += branch;
        end;
      
    end;
    
    public function Combine(test: LocalTestT): boolean;
    begin
      Result := false;
      if Branches.Count=0 then exit;
      if test($'combine[{self.Branches.Count}]', self.AllNodes, nil) then exit;
      
      var any_branch_change := false;
      System.Threading.Tasks.Parallel.ForEach(self.Branches, branch->
      begin
        if branch.Combine(test) then
          any_branch_change := true;
      end);
      if any_branch_change then
      begin
        Result := true;
        var NewAllNodes := self.Branches[0].AllNodes.ToHashSet;
        foreach var branch in self.Branches.Skip(1) do
          NewAllNodes.UnionWith(branch.AllNodes);
        if test($'recombine[{self.Branches.Count}]', NewAllNodes, nil) then
          exit;
      end;
      
      var NewAllNodes := self.Branches[0].AllNodes.ToHashSet;
      var NewBranches := new List<RemovalTree>(self.Branches.Count);
      NewBranches += self.Branches[0];
      
      foreach var branch in self.Branches.Skip(1) do
        branch.TestAndAdd(NewAllNodes, NewBranches, test);
      
      Result := Result or (self.AllNodes.Count <> NewAllNodes.Count);
      self.AllNodes := NewAllNodes;
      self.Branches := NewBranches;
    end;
    
    public procedure TestAndAdd(var NewAllNodes: HashSet<MinimizableNode>; NewBranches: List<RemovalTree>; test: LocalTestT);
    begin
      var hs := NewAllNodes.ToHashSet;
      hs.UnionWith(self.AllNodes);
      if test('sweep', hs, hs.Count-NewAllNodes.Count) then
      begin
        NewAllNodes := hs;
        NewBranches += self;
      end else
      foreach var branch in self.Branches do
        branch.TestAndAdd(NewAllNodes, NewBranches, test);
    end;
    
  end;
  
function MinimizationLayerCounter.Execute: boolean;
begin
  Result := false;
  InvokeValueChanged(0);
  
  {$region test core}
  
  var test_case_without: LocalTestT := (type_descr, without, new_removed_count)->
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
    if new_removed_count<>nil then
    begin
      sb += '[';
      sb += new_removed_count.ToString;
      sb += ']';
    end;
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
  
  {$endregion test core}
  
  var new_removed := new List<HashSet<MinimizableNode>>;
  var all_remove_set := new HashSet<MinimizableNode>;
  {$region wild tests}
  begin
    var max_tests_before_giveup := Round( c.removable_left.Count / ( self.layer ** (1/minimization_p) ) );
    var cts := new System.Threading.CancellationTokenSource;
    
    var giveup_counter := 0;
    var giveup_lock := new object;
    
    var InvokeValueChanged := self.InvokeValueChanged; //ToDo #2197
    foreach var remove_set in ExecMany(
      EnmrRemInds(layer, c.removable_left.Count).Select(inds->MakeFunc1(()->
      begin
        Result := nil;
        var curr_removed := new HashSet<MinimizableNode>(inds.Length);
        foreach var ind in inds do
          curr_removed += c.removable_left[ind];
        
        var new_removed_count: integer;
        lock all_remove_set do
          new_removed_count := curr_removed.Count(n->not all_remove_set.Contains(n));
        
        var test_success := (new_removed_count<>0) and test_case_without('test', curr_removed, new_removed_count);
        
        if test_success then
        begin
          
          foreach var n in curr_removed.ToArray do
            foreach var sub_n in n.Enmr do
              curr_removed += sub_n;
          
          Result := curr_removed;
        end;
        
        lock giveup_lock do
          if test_success and (new_removed_count*2 >= self.layer) then
          begin
            giveup_counter := 0;
            InvokeValueChanged(0);
          end else
          begin
            giveup_counter += 1;
            InvokeValueChanged(giveup_counter.ClampTop(max_tests_before_giveup)/max_tests_before_giveup);
            if giveup_counter>=max_tests_before_giveup then
              cts.Cancel;
          end;
        
      end)),
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
        
        if all_remove_set.Count*self.layer >= c.removable_left.Count then
          cts.Cancel;
        
        self.ReportLineCount(c.n.CountLines(n->not all_remove_set.Contains(n)));
      end;
      
    end;
    
  end;
  {$endregion wild tests}
  
  if new_removed.Count=0 then exit;
  Result := true;
  
  var t := new RemovalTree(new_removed);
  t.Combine(test_case_without);
  c.n.Cleanup(n->n in t.AllNodes);
  self.ReportLineCount(c.n.CountLines(nil));
  var prev_rem_left_c := c.removable_left.Count;
  c.removable_left.RemoveAll(n->n in t.AllNodes);
  self.NodeCountChanged((c.removable_left.Count-prev_rem_left_c)*2 + all_remove_set.Count, nil);
  
  c.n.UnWrapTo(System.IO.Path.Combine(c.base_path, c.EnsureUniqueName($'stable[{c.removable_left.Count}]')), nil);
end;

end.