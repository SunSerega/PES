unit MinimizableCore;

interface

uses PersentDone;

type
  
  MinimizableNode = abstract class
    
    public function Enmr: sequence of MinimizableNode;
    
    protected invulnerable: boolean;
    public property IsInvulnerable: boolean read invulnerable; virtual;
    
    public function Cleanup(is_invalid: MinimizableNode->boolean): MinimizableNode; virtual :=
    is_invalid(self) ? nil : self;
    
    public procedure UnWrapTo(new_base_dir: string; is_valid_node: MinimizableNode->boolean); abstract;
    
    public function ToString: string; override := $'Node[{self.GetType}]';
    
  end;
  
  MinimizableItem = abstract class(MinimizableNode)
    
  end;
  MinimizableList = abstract class(MinimizableNode)
    protected items := new List<MinimizableNode>;
    
    public function Cleanup(is_invalid: MinimizableNode->boolean): MinimizableNode; override;
    begin
      if is_invalid(self) then exit;
      Result := self;
      for var i := 0 to items.Count-1 do
        items[i] := items[i].Cleanup(is_invalid);
      items.RemoveAll(item->item=nil);
    end;
    
    public procedure UnWrapTo(new_base_dir: string; is_valid_node: MinimizableNode->boolean); override :=
    foreach var i in items do
      if is_valid_node(i) then
        i.UnWrapTo(new_base_dir, is_valid_node);
    
    public procedure Add(i: MinimizableNode);
    begin
      self.items += i;
      if i.IsInvulnerable then
        self.invulnerable := true;
    end;
    
    public function Minimize(counter: PersentDoneCounter; test_case: function(descr: string; report: boolean; n: MinimizableNode; is_valid: MinimizableNode->boolean): boolean): boolean;
    
  end;
  
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

function SmartEnmrLayers(c: integer): sequence of integer;
begin
  if c<1 then exit;
  yield c;
  var best_point := Max(1, c div MaxThreadBatch);
  if best_point<>c then
  begin
    yield best_point;
    if best_point<>1 then
      yield 1;
  end;
  for var l := c-1 downto 1 do
    if l<>best_point then
      yield l;
end;

/// l=кол-во элементов которые убирают
/// c=кол-во всех элементов
function EnmrRemInds(l, c: integer): sequence of array of integer;
begin
  if l<0 then raise new System.ArgumentException;
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

function ReorderForAsyncUse<T>(self: sequence of T; can_use: T->boolean): sequence of T; extensionmethod;
const max_skipped = 256*256;
begin
  var skipped := new Queue<T>;
  
  while true do
  begin
    
    foreach var el in self do
      if can_use(el) then
        yield el else
      begin
        if skipped.Count>=max_skipped then
          yield skipped.Dequeue;
        skipped += el;
      end;
    
    if skipped.Count=0 then break;
    yield default(T);
    self := skipped;
    skipped := new Queue<T>;
  end;
  
end;

const max_tests_before_giveup = 128;
function MinimizableList.Minimize(counter: PersentDoneCounter; test_case: function(descr: string; report: boolean; n: MinimizableNode; is_valid: MinimizableNode->boolean): boolean): boolean;
begin
  Result := false;
  
  var removable_left := self.Enmr.Where(n->not n.IsInvulnerable).ToList;
  if removable_left.Count=0 then
  begin
    counter.ManualAddValue(1);
    exit;
  end;
  var scale := 1 / removable_left.Count;
  
  var safely_removed := new HashSet<MinimizableNode>;
  var test_case_without := function(type_descr: string; report: boolean; without: HashSet<MinimizableNode>): boolean ->
  begin
    
    //ToDo #2328
    var is_valid_node := function(n: MinimizableNode): boolean ->
    begin
      Result := true;
      if safely_removed.Contains(n) then Result := false;
      if without.Contains(n) then Result := false;
    end;
    
    var sb := new StringBuilder;
    sb += type_descr;
    sb += ' - (';
    sb += removable_left.Count.ToString;
    sb += '-';
    sb += without.Count.ToString;
    sb += ' = ';
    sb += (removable_left.Count - without.Count).ToString;
    sb += ') [';
    sb += without.Take(5).JoinToString(', ');
    if without.Count>5 then
      sb += ', ...';
    sb += ']';
    
    Result := test_case(sb.ToString, report, self, is_valid_node);
  end;
  
  while true do
  begin
    var inds_usages := new integer[removable_left.Count];
    var c := removable_left.Count;
    
    var cts := new System.Threading.CancellationTokenSource;
    var new_removed := new List<HashSet<MinimizableNode>>;
    
    var since_stable := 0;
    var since_stable_lock := new object;
    
    foreach var remove_set in ExecMany(
      SmartEnmrLayers(c).SelectMany(l->EnmrRemInds(l, c))
      .ReorderForAsyncUse(
        inds->inds.All(ind->inds_usages[ind]=0)
      ),
      inds->
      if inds<>nil then
      begin
        lock inds_usages do foreach var ind in inds do inds_usages[ind] += 1;
        
        Result := new SimpleTask<HashSet<MinimizableNode>>(()->
        begin
          var curr_removed := new HashSet<MinimizableNode>(inds.Length);
          foreach var ind in inds do
            curr_removed += removable_left[ind];
          
          if test_case_without('test', false, curr_removed) then
          begin
            cts.Cancel;
            counter.ManualAddValue(curr_removed.Count*scale*0.5);
            Result := curr_removed;
          end else
          begin
            lock since_stable_lock do
              since_stable += 1;
            if since_stable>=max_tests_before_giveup then
              cts.Cancel;
          end;
          
          lock inds_usages do foreach var ind in inds do inds_usages[ind] -= 1;
        end);
      end,
      cts.Token
    ) do
    begin
      if remove_set=nil then continue;
      new_removed += remove_set;
    end;
    
    if new_removed.Count=0 then break;
    Result := true;
    
    var all_remove_set := new HashSet<MinimizableNode>(new_removed.Sum(remove_set->remove_set.Count));
    foreach var remove_set in new_removed do
      foreach var n in remove_set do
        all_remove_set += n;
    
    if test_case_without('stable', true, all_remove_set) then
    begin
      counter.ManualAddValue(all_remove_set.Count*scale*0.5);
      foreach var n in all_remove_set do
      begin
        safely_removed += n;
        foreach var sub_n in n.Enmr do
          removable_left.Remove(n);
      end;
    end else
      foreach var remove_set in new_removed do
      begin
        if not test_case_without('unstable', true, remove_set) then
        begin
          counter.ManualAddValue(remove_set.Count*scale*-0.5);
          continue;
        end;
        
        counter.ManualAddValue(remove_set.Count*scale*0.5);
        foreach var n in remove_set do
        begin
          safely_removed += n;
          foreach var sub_n in n.Enmr do
            removable_left.Remove(n);
        end;
        
      end;
    
  end;
  
  counter.ManualAddValue(removable_left.Count * scale);
  self.Cleanup(n->safely_removed.Contains(n));
end;

end.