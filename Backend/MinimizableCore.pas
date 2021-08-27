unit MinimizableCore;
{$savepcu false} //ToDo #2346

interface

uses Counters;
uses ThreadUtils;
uses Testing;

type
  
  {$region Node}
  
  MinimizableNode = abstract partial class
    
    protected invulnerable: boolean;
    //ToDo #2462
    public property IsInvulnerable: boolean read boolean(invulnerable); virtual;
    
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); abstract;
    
    public function Cleanup(is_invalid: MinimizableNode->boolean): boolean;
    begin
      Result := is_invalid(self);
      if Result then exit;
      CleanupBody(is_invalid);
    end;
    
    public static function ApplyCleanup(item: MinimizableNode; is_invalid: MinimizableNode->boolean) := (item<>nil) and item.Cleanup(is_invalid);
    public static function ApplyNeedNode(item: MinimizableNode; need_node: MinimizableNode->boolean) := (item<>nil) and ((need_node=nil) or need_node(item));
    
    public function ToString: string; override := $'Node[{self.GetType}]';
    
  end;
  
  MinimizableNodeList<TNode> = sealed class
  where TNode: MinimizableNode;
    private nodes := new List<TNode>;
    
    public function EnmrDirect := nodes.AsEnumerable;
    public property IsEmpty: boolean read nodes.Count=0;
    
    protected invulnerable: boolean;
    public property IsInvulnerable: boolean read invulnerable;
    
    public procedure RemoveAll(f: TNode->boolean) := nodes.RemoveAll(f);
    public procedure Cleanup(is_invalid: MinimizableNode->boolean) := RemoveAll(n->n.Cleanup(is_invalid));
    
    public procedure Add(n: TNode);
    begin
      self.nodes += n;
      //ToDo #????
      if (n as MinimizableNode).IsInvulnerable then
        self.invulnerable := true;
    end;
    public static procedure operator+=(l: MinimizableNodeList<TNode>; n: TNode) := l.Add(n);
    
  end;
  
  MinimizableContainer = abstract class(MinimizableNode)
    
    public function UnWrapTo(new_base_dir: string; need_node: MinimizableNode->boolean): integer; abstract;
    public function CountLines(need_node: MinimizableNode->boolean): integer; abstract;
    
  end;
  
  VulnerableNodeList = sealed partial class(HashSet<MinimizableNode>) end;
  MinimizableNode = abstract partial class
    
    protected procedure AddDirectChildrenTo(l: VulnerableNodeList); abstract;
    protected procedure AddChildrenTo(l: VulnerableNodeList);
    begin
      AddDirectChildrenTo(l);
      if not self.IsInvulnerable then
        //ToDo #2508
        (l as HashSet<MinimizableNode>).Add(self);
    end;
    public function GetAllVulnerableChildren: List<MinimizableNode>;
    begin
      var res := new VulnerableNodeList;
      AddChildrenTo(res);
      Result := res.ToList;
    end;
    
  end;
  
  MinimizableToken = abstract class(MinimizableNode)
    private dependants := new HashSet<MinimizableNode>;
    
    public static procedure operator+=<TNode>(t: MinimizableToken; n: TNode); where TNode: MinimizableNode;
    begin
      t.dependants += MinimizableNode(n);
    end;
    
    public procedure AddDependants(res: HashSet<MinimizableNode>) :=
    foreach var dep in self.dependants do
      if res.Add(dep) and (dep is MinimizableToken(var token)) then
        token.AddDependants(res);
    
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override := dependants.RemoveWhere(is_invalid);
    protected procedure AddDirectChildrenTo(l: VulnerableNodeList); override := AddDependants(l);
    
  end;
  MinimizableTokenMaker = sealed class
    
    private AllTokens := new Dictionary<(System.Type, string), MinimizableToken>;
    public function Get<TToken>(name: string): TToken; where TToken: MinimizableToken, constructor;
    begin
      var cache_key := (typeof(TToken), name);
      var res: MinimizableToken;
      if AllTokens.TryGetValue(cache_key, res) then
        Result := TToken(res) else
      begin
        Result := new TToken;
        AllTokens[cache_key] := Result;
      end;
    end;
    
    public procedure Cleanup(is_invalid: MinimizableNode->boolean);
    begin
      var removed := new List<(System.Type, string)>;
      foreach var kvp in AllTokens do
        if kvp.Value.Cleanup(is_invalid) then
          removed += kvp.Key;
      foreach var key in removed do
        AllTokens.Remove(key);
    end;
    public procedure AddDirectChildrenTo(hs: HashSet<MinimizableNode>) :=
    hs.UnionWith(AllTokens.Values.Cast&<MinimizableNode>);
    
  end;
  MinimizableContainerToken = abstract class(MinimizableToken)
    private sub_tokens := new MinimizableTokenMaker;
    
    public function GetToken<TToken>(name: string): TToken; where TToken: MinimizableToken, constructor;
    begin
      Result := sub_tokens.Get&<TToken>(name);
      dependants.Add(Result);
    end;
    
    protected procedure CleanupBody(is_invalid: MinimizableNode->boolean); override;
    begin
      inherited;
      sub_tokens.Cleanup(is_invalid);
    end;
    protected procedure AddDirectChildrenTo(l: VulnerableNodeList); override;
    begin
      inherited;
      sub_tokens.AddDirectChildrenTo(l);
    end;
    
  end;
  
  VulnerableNodeList = sealed partial class(HashSet<MinimizableNode>)
    
    public static procedure operator+=<TNode>(l: VulnerableNodeList; n: TNode); where TNode: MinimizableNode;
    begin
      if n is MinimizableToken then raise new System.InvalidOperationException;
      //ToDo #2507
      (n as MinimizableNode).AddChildrenTo(l);
    end;
    public static procedure operator+=<TNode>(l: VulnerableNodeList; nl: MinimizableNodeList<TNode>); where TNode: MinimizableNode;
    begin
      foreach var n in nl.EnmrDirect do
        l += n;
    end;
    
  end;
  
  {$endregion Node}
  
  {$region TestInfo}
  
  TestInfo = abstract class
    protected parent: TestInfo;
    
    protected constructor(parent: TestInfo) :=
    self.parent := parent;
    
    public function EnmrNodes: sequence of MinimizableNode; abstract;
    
    public function NeedNode(n: MinimizableNode): boolean; abstract;
    
    public property DisplayName: string read; abstract;
    
  end;
  
  SourceTestInfo = sealed class(TestInfo)
    private nodes: HashSet<MinimizableNode>;
    
    public constructor(nodes: sequence of MinimizableNode);
    begin
      inherited Create(nil);
      self.nodes := nodes.ToHashSet;
    end;
    
    public function EnmrNodes: sequence of MinimizableNode; override := nodes;
    
    public function NeedNode(n: MinimizableNode): boolean; override := n.IsInvulnerable or (n in nodes);
    
    private function GetDisplayName: string;
    begin
      Result := nil;
      raise new System.InvalidOperationException;
    end;
    public property DisplayName: string read GetDisplayName; override;
    
  end;
  
  CommentTestInfo = sealed class(TestInfo)
    private text: string;
    
    public constructor(text: string);
    begin
      inherited Create(nil);
      self.text := text;
    end;
    
    public function EnmrNodes: sequence of MinimizableNode; override := new MinimizableNode[0];
    
    public function NeedNode(n: MinimizableNode): boolean; override;
    begin
      Result := false;
      raise new System.NotSupportedException;
    end;
    
    public property DisplayName: string read text; override;
    
  end;
  
  RemTestInfo = abstract class(TestInfo)
    private rem: HashSet<MinimizableNode>;
    
    public property Parent: TestInfo read TestInfo(inherited parent);
    
    private tr: TestResult;
    private res: boolean;
    public event TestDone: (TestResult, boolean)->();
    protected procedure SetResult(tr: TestResult; res: boolean);
    begin
      var TestDone := self.TestDone;
      lock self do
      begin
        if self.tr<>nil then raise new System.NotSupportedException;
        self.tr := tr;
        self.res := res;
      end;
      if TestDone<>nil then
      begin
        TestDone(tr, res);
        TestDone := nil; // because self.tr was nil
      end;
    end;
    public procedure OnTestDone(p: (TestResult, boolean)->()) :=
    lock self do
      if self.tr=nil then
        self.TestDone += p else
        p(tr, res);
    
    protected constructor(removing: HashSet<MinimizableNode>; parent: TestInfo);
    begin
      inherited Create(parent);
      if Parent=nil then raise new System.NotSupportedException;
      self.rem := removing;
    end;
    ///--
    private constructor := raise new System.InvalidOperationException;
    
//    public property Removing: HashSet<MinimizableNode> read rem;
    
    public function EnmrNodes: sequence of MinimizableNode; override := Parent.EnmrNodes.Where(n->not rem.Contains(n));
    
    public function NeedNode(n: MinimizableNode): boolean; override;
    begin
      Result := false;
      if not Parent.NeedNode(n) then exit;
      if n in rem then exit;
      Result := true;
    end;
    
  end;
  
  WildTestInfo = sealed class(RemTestInfo)
    private actually_removed: integer;
    
    public constructor(removing: HashSet<MinimizableNode>; actually_removed: integer; parent: TestInfo);
    begin
      inherited Create(removing, parent);
      self.actually_removed := actually_removed;
    end;
    
    public property DisplayName: string read $'Wild: {parent.EnmrNodes.Count} - {rem.Count} ({actually_removed}) => {self.EnmrNodes.Count}'; override;
    
  end;
  
  ContainerTestInfo = abstract class(RemTestInfo)
    
    public event SubTestAdded: TestInfo->();
    
    public procedure AddSubTest(test: TestInfo);
    begin
      var SubTestAdded := self.SubTestAdded;
      if SubTestAdded<>nil then SubTestAdded(test);
    end;
    
  end;
  
  CombineTestInfo = sealed class(ContainerTestInfo)
    
    public property DisplayName: string read $'Combine: {parent.EnmrNodes.Count} - {rem.Count} => {self.EnmrNodes.Count}'; override;
    
  end;
  
  RecombineTestInfo = sealed class(RemTestInfo)
    
    public property DisplayName: string read $'Recombine: {parent.EnmrNodes.Count} - {rem.Count} => {self.EnmrNodes.Count}'; override;
    
  end;
  
  AutoTestInfo = sealed class(RemTestInfo)
    
    public constructor(removing: HashSet<MinimizableNode>; tr: TestResult; parent: TestInfo);
    begin
      inherited Create(removing, parent);
      self.SetResult(tr, true);
    end;
    
    public property DisplayName: string read $'Auto: {parent.EnmrNodes.Count} - {rem.Count} => {self.EnmrNodes.Count}'; override;
    
  end;
  
  SweepTestInfo = sealed class(ContainerTestInfo)
    private actually_removed: integer;
    
    protected constructor(removing: HashSet<MinimizableNode>; actually_removed: integer; parent: TestInfo);
    begin
      inherited Create(removing, parent);
      self.actually_removed := actually_removed;
    end;
    
    public property DisplayName: string read $'Sweep: {parent.EnmrNodes.Count} - {rem.Count} ({actually_removed}) => {self.EnmrNodes.Count}'; override;
    
  end;
  
  {$endregion TestInfo}
  
  {$region Counter}
  
  InternalMinimizationContext = record
    public nc: MinimizableContainer;
    public expected_tr: TestResult;
    public removable_left: List<MinimizableNode>;
    public start_layer: integer;
    public base_path: string;
    public exec_test: (string, TestInfo)->(TestResult, boolean);
    public source_test_info: TestInfo;
    
    private unique_names := new HashSet<string>;
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
    
    public constructor(nc: MinimizableContainer; expected_tr: TestResult; removable_left: List<MinimizableNode>; base_path: string; exec_test: (string, TestInfo)->(TestResult, boolean));
    begin
      self.nc := nc;
      self.expected_tr := expected_tr;
      self.removable_left := removable_left;
      self.start_layer := GetLayerForCount;
      self.base_path := base_path;
      self.exec_test := exec_test;
      self.source_test_info := new SourceTestInfo(removable_left.ToArray);
    end;
    
  end;
  
  MinimizationLayerCounter = sealed class(Counter)
    private c: InternalMinimizationContext;
    private layer: integer;
    
    public property FirstNode: MinimizableContainer read c.nc;
    
    public function Execute: boolean;
    
    protected event ReportLineCount: integer->();
    protected event ReportMinimizedCount: integer->();
    protected event StableDirCreated: string->();
    public event NewTestInfo: TestInfo->();
    
    protected procedure InvokeNewTestInfo(ti: TestInfo);
    begin
      var NewTestInfo := self.NewTestInfo;
      if NewTestInfo<>nil then NewTestInfo(ti);
    end;
    
    public property LayerRemoveCount: integer read layer;
    
    protected constructor(c: InternalMinimizationContext; layer: integer);
    begin
      self.c := c;
      self.layer := layer;
    end;
    private constructor := raise new System.InvalidOperationException;
    
    private total_tests: integer;
    public property DisplayName: string read $'{total_tests} tests by {layer} items';
    
    public event DisplayNameUpdated: ()->();
    protected procedure InvokeDisplayNameUpdated;
    begin
      var DisplayNameUpdated := DisplayNameUpdated;
      if DisplayNameUpdated<>nil then DisplayNameUpdated();
    end;
    
    public procedure SetTotalTests(total_tests: integer);
    begin
      self.total_tests := total_tests;
      InvokeDisplayNameUpdated;
    end;
    
  end;
  
  MinimizationCounter = sealed class(Counter)
    private c: InternalMinimizationContext;
    
    public function Execute: boolean;
    
    public event ReportLineCount: integer->();
    
    public event LayerAdded: MinimizationLayerCounter->();
    protected procedure InvokeLayerAdded(l: MinimizationLayerCounter);
    begin
      var LayerAdded := self.LayerAdded;
      if LayerAdded<>nil then LayerAdded(l);
    end;
    
    private last_stable_dir: string := nil;
    public property LastStableDir: string read last_stable_dir;
    
    public constructor(nc: MinimizableContainer; expected_tr: TestResult; base_path: string; exec_test: (string, TestInfo)->(TestResult, boolean));
    begin
      var removable_left := nc.GetAllVulnerableChildren;
      
      self.c := new InternalMinimizationContext(
        nc,
        expected_tr,
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
  
  //ToDo Всё же плохо... 75k тестов чтоб уменьшить 8k => 4k
  // - Таким образом даже удаление по 1 элементу - быстрее
  // - Надо, наверное, проходить сначала быстрые уровни от c.GetLayerForCount до 1,
  // --- А затем длинные назад от 1 до c.GetLayerForCount
  // - Быстрые уровни должны считать, сколько тестов будут иметь смысл, то есть удалят не меньше строк чем (кол-во сделанных тестов)/(k=2?) (потому что даже в тестах по 1 - не все будут удалены)
  // --- Разбить предугадывание успешности и предугадывание кол-во реально убранных строк на две части
  // - Тем временем медленные уровни пусть всё ещё считаю так, чтоб все элементы попыталось удалить хотя бы по 1 разу
  var curr_layer := c.start_layer;
  var initial_removables_count := c.removable_left.Count;
  
//  loop 4 do curr_layer := curr_layer div 2;
  
  while true do
  begin
    var InvokeValueChanged := self.InvokeValueChanged; //ToDo #2197
    
    if c.removable_left.Count=0 then
    begin
      self.InvokeValueChanged(1);
      exit;
    end;
    
//    if (l=nil) or (l.layer <> curr_layer) then
    var l := new MinimizationLayerCounter(c, curr_layer);
    
    l.ReportLineCount += line_count->self.ReportLineCount(line_count);
    l.ReportMinimizedCount += minimized_count->InvokeValueChanged(1 - (c.removable_left.Count - minimized_count) / initial_removables_count);
    l.StableDirCreated += dir->
    begin
      self.last_stable_dir := dir;
    end;
    
    self.InvokeLayerAdded(l);
    
    if l.Execute then
    begin
      c.source_test_info := new SourceTestInfo(c.removable_left);
      Result := true;
    end;// else
    if curr_layer>1 then
      curr_layer := curr_layer div 2 else
      break;
    
    curr_layer := curr_layer.ClampTop(c.GetLayerForCount);
  end;
  
end;

type
  RemovalTree = sealed class
    private AllNodes := new HashSet<MinimizableNode>;
    private Branches := new List<RemovalTree>;
    
    public constructor(l: List<HashSet<MinimizableNode>>);
    begin
      if l.Count=0 then raise new System.NotSupportedException;
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
          self.AllNodes.UnionWith(t.AllNodes);
          self.Branches += t;
          last_ind += c;
        end;
        
        {$ifdef DEBUG}
        if last_ind<>l.Count then
          raise new System.InvalidOperationException;
        {$endif DEBUG}
        
      end else
      if l.Count=1 then
      begin
        self.AllNodes := l.Single;
        self.Branches := nil;
      end else
        foreach var hs in l do
        begin
          var branch := new RemovalTree(|hs|.ToList);
          self.AllNodes.UnionWith(hs);
          self.Branches += branch;
        end;
      
    end;
    private constructor := raise new System.InvalidOperationException;
    
    // Result=true when change happened
    public function Combine(source_test: TestInfo; expected_tr: TestResult; test_func: RemTestInfo->boolean; add_as_sub_test: TestInfo->()): boolean;
    begin
      Result := false;
      // Only single node batch exists
      if Branches=nil then exit;
      
      var main_combine_test := new CombineTestInfo(self.AllNodes, source_test);
      add_as_sub_test(main_combine_test);
      if test_func(main_combine_test) then exit;
      
      var any_branch_change := false;
      System.Threading.Tasks.Parallel.ForEach(self.Branches, branch->
      begin
        if branch.Combine(source_test, expected_tr, test_func, main_combine_test.AddSubTest) then
          any_branch_change := true;
      end);
      if any_branch_change then
      begin
        Result := true;
        var NewAllNodes := self.Branches[0].AllNodes.ToHashSet;
        foreach var branch in self.Branches.Skip(1) do
          NewAllNodes.UnionWith(branch.AllNodes);
        var recombine_test := new RecombineTestInfo(NewAllNodes, source_test);
        main_combine_test.AddSubTest(recombine_test);
        if test_func(recombine_test) then
        begin
          self.AllNodes := NewAllNodes;
          exit;
        end;
      end;
      
      var NewAllNodes := self.Branches[0].AllNodes.ToHashSet;
      var NewBranches := new List<RemovalTree>(self.Branches.Count);
      NewBranches += self.Branches[0];
      
      var last_test: TestInfo := new AutoTestInfo(NewAllNodes, expected_tr, source_test);
      main_combine_test.AddSubTest(last_test);
      foreach var branch in self.Branches.Skip(1) do
        branch.TestAndAdd(NewAllNodes, NewBranches, last_test, main_combine_test, test_func);
      main_combine_test.AddSubTest(new CommentTestInfo($'Stable: {last_test.EnmrNodes.Count}'));
      
      Result := Result or (self.AllNodes.Count <> NewAllNodes.Count);
      self.AllNodes := NewAllNodes;
      self.Branches := NewBranches;
    end;
    
    public procedure TestAndAdd(var NewAllNodes: HashSet<MinimizableNode>; NewBranches: List<RemovalTree>; var source_test: TestInfo; cont: ContainerTestInfo; test_func: RemTestInfo->boolean);
    begin
      var hs := self.AllNodes.ToHashSet;
      hs.ExceptWith(NewAllNodes);
      if hs.Count = 0 then
      begin
        cont.AddSubTest(new CommentTestInfo($'Skipped: {source_test.EnmrNodes.Count} - {self.AllNodes.Count} ({hs.Count})'));
        exit;
      end;
      var sweep_test := new SweepTestInfo(self.AllNodes, hs.Count, source_test);
      cont.AddSubTest(sweep_test);
      if test_func(sweep_test) then
      begin
        source_test := sweep_test;
//        NewAllNodes.UnionWith(self.AllNodes);
        NewAllNodes.UnionWith(hs);
        NewBranches += self;
      end else
      if self.Branches<>nil then
        foreach var branch in self.Branches do
          branch.TestAndAdd(NewAllNodes, NewBranches, source_test, sweep_test, test_func);
    end;
    
  end;
  
function MinimizationLayerCounter.Execute: boolean;
begin
  Result := false;
  InvokeValueChanged(0);
  
  {$region test core}
  
  var test_case := function(rti: RemTestInfo; is_integrity_test: boolean): boolean ->
  begin
    var curr_test_dir := System.IO.Path.Combine(c.base_path, c.EnsureUniqueName('test'));
    c.nc.UnWrapTo(curr_test_dir, rti.NeedNode);
    var (tr, res) := c.exec_test(curr_test_dir, rti);
    if is_integrity_test and not res then
      raise new System.InvalidOperationException($'{curr_test_dir}: [{#10}{tr.GetShortDescription}{#10}]');
    try
      System.IO.Directory.Delete(curr_test_dir, true);
    except
      on e: Exception do
        System.Windows.MessageBox.Show(e.ToString);
    end;
    rti.SetResult(tr, res);
    Result := res;
  end;
  var simple_test_case := function(rti: RemTestInfo): boolean ->test_case(rti, false);
  
  {$endregion test core}
  
  var new_removed := new List<HashSet<MinimizableNode>>;
  var all_remove_set := new HashSet<MinimizableNode>;
  var global_need_node := function(n: MinimizableNode): boolean -> c.source_test_info.NeedNode(n) and not (n in all_remove_set);
  {$region wild tests}
  begin
    
    {$region max_test_before_abort}
    // s(x) = max_test_before_abort   : Кол-во тестов перед сбросом
    // x    = successful_c            : Кол-во успешных тестов
    // n    = c.removable_left.Count  : Кол-во удалябельных элементов
    // l    = self.layer              : Кол-во удаляемых каждой операцией элементов (текущий уровень)
    // k    = max_tests_k             : Коэфициент согнутости графика s (чем ближе k->(1+0)*n - тем быстрее s увеличивается в начале)
    // 
    // Нужна такая s, чтоб:
    // 1. Если успешных тестов нет, то выйти надо после n/l тестов                      : s(0)=n/l
    // 2. При каждом успешном тесте добавлять к верхней границе падающее значение       : dds/dx^2<0, но ds/dx>0
    // 3. Если все тесты успешные - после последнего надо чтоб все тесты были разрешены : s(n)=n
    // 
    // Возьмём график k - 1/x, т.к. он сразу удовлетворяет п.2.
    // (в графике k2/x коэфициент k2 маштабирует одновременно x и y, поэтому его проще оставить 1)
    // Маштабируем сдвигаем значения x так, чтоб:
    // - x=0 -> s(x)=n/l
    // - x=n -> s(x)=n
    // После всех приведений получается что k может быть произвольным
    // (но даёт мусор при k<1, потому что график выворачивает наизнанку)
    // Берём k такой, чтоб (ds/dx)(0)=s(0), то есть первый успешный тест практически удваивает s
    // 
    // График:
    // https://www.desmos.com/calculator/aqatviizx6
    
    //ToDo А что если n уменьшится, а start_layer так и останется?
    var max_tests_k := c.removable_left.Count *
      (c.start_layer-1-real(c.removable_left.Count)*c.start_layer) /
      (c.start_layer-1-real(c.removable_left.Count))/c.start_layer;
    var floor_ndl := c.removable_left.Count div self.layer; // Floor(n/l);
    
    var max_test_before_abort_f := function(successful_c: integer): integer->
    begin
      //ToDo successful_c идёт до n, поэтому x никогда не будет больше n/l
      // - Это с самого начала продумано небыло...
      // - Если s(n/l)=n - график получается слишком резкий, даже при больших k
      var x := successful_c / self.layer;
      var n := c.removable_left.Count;
      var l := self.layer;
      var k := max_tests_k;
      if l=1 then
      begin
        Result := n;
        exit;
      end;
      var xmxdl := x-x/l;
      Result := Ceil( floor_ndl + xmxdl * (k-floor_ndl) / (k+xmxdl-n) );
    end;
    var max_test_before_abort := floor_ndl;
    SetTotalTests(max_test_before_abort);
    
    var successful_c := 0;
    var done_c := 0;
    var test_done_lock := new object;
    
    var cts := new System.Threading.CancellationTokenSource;
    {$endregion max_test_before_abort}
    
    InvokeNewTestInfo( new CommentTestInfo($'Layer start: {max_test_before_abort} / {c.removable_left.Count}') );
    
    var InvokeValueChanged := self.InvokeValueChanged; //ToDo #2197
    foreach var remove_set in ExecMany(
      EnmrRemInds(layer, c.removable_left.Count).Select(inds->MakeFunc1(()->
      begin
        Result := nil;
        var curr_removed := new HashSet<MinimizableNode>(inds.Length);
        foreach var ind in inds do
          curr_removed += c.removable_left[ind];
        
        foreach var token in curr_removed.OfType&<MinimizableToken>.ToList do
          token.AddDependants(curr_removed);
        
        var new_removed_count: integer;
        lock all_remove_set do
        begin
          new_removed_count := curr_removed.Count(n->not all_remove_set.Contains(n));
//          $'{all_curr_removed.Count} without {all_remove_set.Count} = {new_removed_count}'.Println;
        end;
        
        var test_success := new_removed_count <> 0;
        if test_success then
        begin
          var ti := new WildTestInfo(curr_removed, new_removed_count, c.source_test_info);
          self.InvokeNewTestInfo(ti);
          test_success := simple_test_case(ti);
        end;
        
        if test_success then
        begin
          var l := new VulnerableNodeList;
          foreach var n in curr_removed do
            n.AddChildrenTo(l);
//          l.Except(curr_removed).PrintLines(n->n.GetType);
//          Writeln('='*30);
          Result := l as HashSet<MinimizableNode>;
        end;
        
//        if new_removed_count*2 < self.layer then test_success := false;
        lock test_done_lock do
        begin
          done_c += 1;
          successful_c += new_removed_count*integer(test_success);
          max_test_before_abort := max_test_before_abort_f(successful_c);
          SetTotalTests(max_test_before_abort);
          if (done_c>=max_test_before_abort) and not cts.IsCancellationRequested then
          begin
            cts.Cancel;
            InvokeNewTestInfo( new CommentTestInfo('Abort: Not enough of a result') );
          end;
          InvokeValueChanged( done_c.ClampTop(max_test_before_abort) / max_test_before_abort );
        end;
        
      end)),
      cts.Token
    ) do
    begin
      if remove_set=nil then continue;
      new_removed += remove_set;
      
      lock all_remove_set do
      begin
        all_remove_set.UnionWith(remove_set);
        self.ReportMinimizedCount(all_remove_set.Count);
        
//        if (all_remove_set.Count*2 >= c.removable_left.Count) and not cts.IsCancellationRequested then
//        begin
//          cts.Cancel;
//          InvokeNewTestInfo( new CommentTestInfo('Abort: Too much of a result') );
//        end;
        
        self.ReportLineCount(c.nc.CountLines(global_need_node));
      end;
      
    end;
    
  end;
  {$endregion wild tests}
  
  if new_removed.Count=0 then exit;
  Result := true;
  
  var t := new RemovalTree(new_removed);
  t.Combine(c.source_test_info, c.expected_tr, simple_test_case, self.InvokeNewTestInfo);
  c.removable_left.RemoveAll(n->n in t.AllNodes);
  all_remove_set := t.AllNodes;
  
  {$ifdef DEBUG}
  begin
    var rti := new RecombineTestInfo(t.AllNodes, c.source_test_info);
    self.InvokeNewTestInfo(rti);
    if not test_case(rti, true) then
      raise new System.InvalidOperationException;
  end;
  {$endif DEBUG}
  
  var stable_dir := System.IO.Path.Combine(c.base_path, c.EnsureUniqueName($'stable[{c.removable_left.Count}]'));
  var line_count := c.nc.UnWrapTo(stable_dir, global_need_node);
  self.ReportLineCount(line_count);
  
  var StableDirCreated := self.StableDirCreated;
  if StableDirCreated<>nil then StableDirCreated(stable_dir);
  
  self.ReportMinimizedCount(0);
  InvokeNewTestInfo( new CommentTestInfo('Layer sealed') );
end;

end.