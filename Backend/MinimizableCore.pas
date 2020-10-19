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

//function SmartEnmrLayers(c: integer; first: boolean): sequence of integer;
//begin
//  if c<1 then exit;
//  if first or (c=1) then
//  begin
//    yield c;
//    first := false;
//  end;
////  var best_point := Max(1, c div MaxThreadBatch);
////  if best_point<>c then
////  begin
////    yield best_point;
////    if best_point<>1 then
////      yield 1;
////  end;
//  for var l := {2}1 to c-1 do
////    if l<>best_point then
//      yield l;
//end;

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

type
  ReorderUsability = (RU_now, RU_later, RU_discard);
  
  ReorderedItemContainer<T> = abstract class end;
  ReorderedItemContainerItem<T> = sealed class(ReorderedItemContainer<T>)
    public val: T;
    public constructor(val: T) := self.val := val;
    private constructor := raise new System.InvalidOperationException;
  end;
  ReorderedItemContainerSkip<T> = sealed class(ReorderedItemContainer<T>) end;
  
function ReorderForAsyncUse<T>(self: sequence of T; can_use: T->ReorderUsability): sequence of ReorderedItemContainer<T>; extensionmethod;
const max_skipped = 256*256;
begin
  var skipped := new Queue<T>;
  
  while true do
  begin
    
    foreach var el in self do
      case can_use(el) of
        
        RU_now: yield new ReorderedItemContainerItem<T>(el);
        
        RU_later:
        if skipped.Count < max_skipped then
          skipped += el;
        
        RU_discard: ;
        
        else raise new System.NotSupportedException;
      end;
    
    if skipped.Count=0 then break;
    yield new ReorderedItemContainerSkip<T>;
    self := skipped.ToArray;
    skipped.Clear;
  end;
  
end;

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
    foreach var n in without do
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
    
    Result := test_case(sb.ToString, report, self, is_valid_node);
  end;
  
  var default_max_tests_before_giveup := 128;
  var start_layer := Max(1, removable_left.Count div MaxThreadBatch);
  var p := 4.0; // 1..∞
  
  var max_tests_before_giveup := default_max_tests_before_giveup;
  var curr_layer := start_layer;
  while true do
  begin
    var inds_usages := new integer[removable_left.Count];
    var c := removable_left.Count;
    
    var cts := new System.Threading.CancellationTokenSource;
    var new_removed := new List<HashSet<MinimizableNode>>;
    
    var since_stable := 0;
    var since_stable_lock := new object;
    
    foreach var remove_set in ExecMany(
      EnmrRemInds(curr_layer, c)
      .ReorderForAsyncUse(inds->
      begin
        Result := RU_now;
        foreach var ind in inds do
        begin
          var use_c := inds_usages[ind];
          if use_c=0 then
            continue else
          if use_c>0 then
            Result := RU_later else
          if use_c<0 then
          begin
            Result := RU_discard;
            break;
          end;
        end;
      end),
      inds_cont->
      begin
        match inds_cont with
          
          ReorderedItemContainerItem<array of integer>(var inds_cont_item):
          begin
            var inds := inds_cont_item.val;
            lock inds_usages do foreach var ind in inds do inds_usages[ind] += 1;
            
            Result := new SimpleTask<HashSet<MinimizableNode>>(()->
            begin
              var curr_removed := new HashSet<MinimizableNode>(inds.Length);
              foreach var ind in inds do
                curr_removed += removable_left[ind];
              
              if test_case_without('test', false, curr_removed) then
              begin
                lock since_stable_lock do since_stable := 0;
                // .SelectMany.Distinct будет работает только пока
                // .ReorderForAsyncUse не пропускает пересекающиеся последовательности
                counter.ManualAddValue(curr_removed.SelectMany(n->n.Enmr).Distinct.Count*scale*0.5);
                Result := curr_removed;
              end else
              lock since_stable_lock do
              begin
                since_stable += 1;
                if since_stable>=max_tests_before_giveup then
                  cts.Cancel;
              end;
              
              lock inds_usages do foreach var ind in inds do inds_usages[ind] := integer.MinValue;
            end);
            
          end;
          
          ReorderedItemContainerSkip<array of integer>(var inds_cont_skip): Result := nil;
          
        end;
      end,
      cts.Token
    ) do
    begin
      if remove_set=nil then continue;
      new_removed += remove_set;
      if not cts.IsCancellationRequested and (new_removed.Sum(remove_set->remove_set.Count) >= removable_left.Count div 2) then
        cts.Cancel;
    end;
    
    if new_removed.Count=0 then
      if curr_layer>1 then
      begin
        curr_layer := curr_layer div 2;
        max_tests_before_giveup := Round(default_max_tests_before_giveup ** (
          (LogN(default_max_tests_before_giveup, c)-1) *
          ( (start_layer-curr_layer)/(start_layer-1) ) ** p
        +1));
        continue;
      end else
        break;
    Result := true;
    
    var all_remove_set := new HashSet<MinimizableNode>(new_removed.Sum(remove_set->remove_set.Count));
    foreach var remove_set in new_removed do
      foreach var n in remove_set do
        all_remove_set += n;
    
    if test_case_without('stable', true, all_remove_set) then
    begin
      var rem_c := 0;
      foreach var n in all_remove_set do
      begin
        safely_removed += n;
        foreach var sub_n in n.Enmr do
          if removable_left.Remove(n) then
            rem_c += 1;
      end;
      counter.ManualAddValue(rem_c*scale*0.5);
    end else
      foreach var remove_set in new_removed do
      begin
        if not test_case_without('unstable', true, remove_set) then
        begin
          counter.ManualAddValue(remove_set.SelectMany(n->n.Enmr).Distinct.Count*scale*-0.5);
          continue;
        end;
        
        var rem_c := 0;
        foreach var n in remove_set do
        begin
          safely_removed += n;
          foreach var sub_n in n.Enmr do
            if removable_left.Remove(n) then
              rem_c += 1;
        end;
        counter.ManualAddValue(rem_c*scale*0.5);
        
      end;
    
    if curr_layer>removable_left.Count then
      curr_layer := removable_left.Count;
  end;
  
//  counter.ManualAddValue(removable_left.Count * scale);
  self.Cleanup(n->safely_removed.Contains(n));
end;

end.