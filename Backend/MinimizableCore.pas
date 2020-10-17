unit MinimizableCore;

interface

uses PersentDone;

type
  
  MinimizableNode = abstract class
    
    public function Enmr: sequence of MinimizableNode; abstract;
    
    public property ReadableName: string read $'Node[{self.GetType}]'; virtual;
    public function ToString: string; override := ReadableName;
    
  end;
  
  MinimizableItem = abstract class(MinimizableNode)
    
    public function Enmr: sequence of MinimizableNode; override := |self as MinimizableNode|;
    
  end;
  MinimizableList = abstract class(MinimizableNode)
    protected items := new List<MinimizableNode>;
    
    public function Enmr: sequence of MinimizableNode; override;
    begin
      yield self;
      foreach var item in items do
        yield sequence item.Enmr;
    end;
    
    public function DoAllMinimizing(counter: PersentDoneCounter; test_case: MinimizableNode->boolean): boolean;
    
  end;
  
  ShadowMinimizableListBase = abstract class(MinimizableNode)
    private org: MinimizableList;
    public static default_batch_size := System.Environment.ProcessorCount+1;
    
    public constructor(l: MinimizableList) := self.org := l;
    private constructor := raise new System.InvalidOperationException;
    
    public function UnWrap: MinimizableList; abstract;
    
  end;
  
  ShadowOrderedMinimizableList = sealed class(ShadowMinimizableListBase)
    private removed_range: IntRange;
    
    public constructor(l: MinimizableList; removed_range: IntRange);
    begin
      inherited Create(l);
      
      {$ifdef DEBUG}
      if removed_range.Low<0 then
        raise new System.ArgumentOutOfRangeException('Low');
      if removed_range.High>=l.items.Count then
        raise new System.ArgumentOutOfRangeException('High');
      {$endif DEBUG}
      
      self.removed_range := removed_range;
    end;
    private constructor := raise new System.InvalidOperationException;
    
    public static function MakeBatch(l: MinimizableList): array of ShadowMinimizableListBase;
    begin
      Result := new ShadowMinimizableListBase[Min(default_batch_size, l.items.Count)];
      var uneven_c: integer;
      var c := System.Math.DivRem(l.items.Count, Result.Length, uneven_c);
      var n := 0;
      for var i := 0 to Result.Length-1 do
      begin
        var next_n := n + c + integer(i<uneven_c);
        Result[i] := new ShadowOrderedMinimizableList(l, n..next_n-1);
        n := next_n;
      end;
    end;
    
    public function Enmr: sequence of MinimizableNode; override;
    begin
      yield org;
      for var i := 0 to removed_range.Low-1 do
        yield sequence org.items[i].Enmr;
      for var i := removed_range.High+1 to org.items.Count-1 do
        yield sequence org.items[i].Enmr;
    end;
    
    public property ReadableName: string read $'Ordered from {org.items[removed_range.Low].ReadableName} to {org.items[removed_range.High].ReadableName} (c={removed_range.Count})'; override;
    
    public function UnWrap: MinimizableList; override;
    begin
      org.items.RemoveRange(removed_range.Low, removed_range.Count);
      Result := org;
      self.org := nil;
    end;
    
  end;
  ShadowDisorderedMinimizableList = sealed class(ShadowMinimizableListBase)
    private removed_items: HashSet<MinimizableNode>;
    
    public constructor(l: MinimizableList; removed_inds: array of integer);
    begin
      inherited Create(l);
      
      {$ifdef DEBUG}
      for var i := 0 to removed_inds.Length-1 do
        if not (removed_inds[i] in 0..l.items.Count) then
          raise new System.ArgumentOutOfRangeException($'inds[{i}]');
      {$endif DEBUG}
      
      self.removed_items := new HashSet<MinimizableNode>(removed_inds.Length);
      foreach var ind in removed_inds do
        self.removed_items += l.items[ind];
    end;
    private constructor := raise new System.InvalidOperationException;
    
    private static function GetLayerCount(l: integer; c: integer): integer;
    begin
      if l<1 then raise new System.ArgumentException;
      case l of
        1: Result := c;
        2: Result := (c-1)*c div 2;
        else
        begin
          Result := 0;
          for var i := 1 to c-l+1 do
            Result += GetLayerCount(l-1, c-i);
        end;
      end;
    end;
    public static function MakeBatch(l: MinimizableList): array of ShadowMinimizableListBase;
    const max_batches = 100;
    begin
      var max_c := max_batches*default_batch_size;
      var items_c := l.items.Count;
      
      var c := 0;
      var last_layer := items_c-1;
      
      for var i := 1 to last_layer do
      begin
        var new_c := c + GetLayerCount(i, items_c);
        
        if new_c>=max_c then
        begin
          last_layer := i - integer(c>max_c);
//          c := max_c; //ToDo Если частичный уровень будет считаться
          break;
        end;
        
        c := new_c;
      end;
      
      Result := new ShadowMinimizableListBase[c];
      
      var ind := 0;
      for var i := 1 to last_layer do
      begin
        var rem_inds := new List<integer>(i);
        
        while true do
          if rem_inds.Count<i then
            rem_inds += rem_inds.Count=0 ? 0 : rem_inds.Last+1 else
          begin
            Result[ind] := new ShadowDisorderedMinimizableList(l, rem_inds.ToArray);
            ind += 1;
            
            while true do
            begin
              var last_ind := rem_inds[rem_inds.Count-1] + 1;
              if last_ind=items_c-(i-rem_inds.Count) then
              begin
                rem_inds.RemoveLast;
                if rem_inds.Count=0 then break;
              end else
              begin
                rem_inds[rem_inds.Count-1] := last_ind;
                break;
              end;
            end;
            
            if rem_inds.Count=0 then break;
          end;
        
      end;
      
    end;
    
    public function Enmr: sequence of MinimizableNode; override;
    begin
      yield org;
      for var i := 0 to org.items.Count-1 do
        if not removed_items.Contains(org.items[i]) then
          yield sequence org.items[i].Enmr;
    end;
    
    public property ReadableName: string read $'Disordered ' + removed_items.Select(item->item.ReadableName).JoinToString; override;
    
    public function UnWrap: MinimizableList; override;
    begin
      org.items.RemoveAll(item->item in self.removed_items);
      Result := org;
      self.org := nil;
    end;
    
  end;
  
implementation

uses ThreadUtils;

function EnmrMinimizingStrats(l: MinimizableList): sequence of array of ShadowMinimizableListBase;
begin
  yield l=nil ? nil : ShadowOrderedMinimizableList    .MakeBatch(l);
  yield l=nil ? nil : ShadowDisorderedMinimizableList .MakeBatch(l);
end;

function MinimizableList.DoAllMinimizing(counter: PersentDoneCounter; test_case: MinimizableNode->boolean): boolean;
begin
  var minimization_any_res := false;
  
  counter.SplitTasks(2, (task_ind, counter)->
  case task_ind of
    
    0:
    begin
      var batch_enmr: IEnumerator<array of ShadowMinimizableListBase> := EnmrMinimizingStrats(self).GetEnumerator;
      
      counter.SplitTasks(EnmrMinimizingStrats(nil).Count, (batch_ind, counter)->
      begin
        if not batch_enmr.MoveNext then raise new System.InvalidOperationException;
        var batch := batch_enmr.Current;
        
        var batch_res := SimpleTask&<boolean>.ExecMany(counter, batch, (l, counter)->
          new SimpleTask<boolean>(()->
          begin
            Result := test_case(l);
            counter.ManualAddValue(1);
          end)
        );
        if batch_res.Any(res_ok->res_ok) then
          minimization_any_res := true else
          exit;
        
        var items_backup := self.items.ToList;
        
        for var i := batch.Length-1 downto 0 do
          if batch_res[i] then
            batch[i].UnWrap;
        
        if not test_case(self) then
        begin
          self.items := items_backup;
          
          for var i := batch.Length-1 downto 0 do
            if batch_res[i] then
            begin
              items_backup := self.items.ToList;
              batch[i].UnWrap;
              if not test_case(self) then self.items := items_backup;
            end;
          
        end;
        
      end);
      
    end;
    
    1:
    begin
      var sub_lists := self.items.OfType&<MinimizableList>.ToList;
      
      counter.SplitTasks(sub_lists.Count, (sub_list_ind, counter)->
        if sub_lists[sub_list_ind].DoAllMinimizing(counter, test_case) then
          minimization_any_res := true
      );
      
    end;
    
    else raise new System.InvalidOperationException;
  end);
  
  Result := minimization_any_res;
end;

end.