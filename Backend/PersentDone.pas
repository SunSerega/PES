unit PersentDone;

type
  PersentDoneCounter = sealed class
    public event ValueChanged: procedure(new_v: real);
    public event SubCountersAdded: procedure(pos, size: real; count: integer);
    private ValueAdded: real->();
    private val: real;
    
    public procedure ManualAddValue(dv: real) := ValueAdded(dv);
    public procedure Reset;
    begin
      ValueChanged -= ValueChanged;
      val := 0;
    end;
    
    public constructor;
    begin
      self.ValueAdded := dv->
      begin
        val += dv;
        var ValueChanged := self.ValueChanged;
        if ValueChanged<>nil then ValueChanged(val);
      end;
    end;
    private constructor(parent: PersentDoneCounter; scale: real);
    begin
      self.ValueAdded := dv->
      begin
        val += dv;
        parent.ValueAdded(dv*scale);
        var ValueChanged := self.ValueChanged;
        if ValueChanged<>nil then ValueChanged(val);
      end;
    end;
    
    public procedure SplitTasks(count: integer; proc: (integer, PersentDoneCounter)->());
    begin
      if count=0 then
      begin
        self.ManualAddValue(1);
        exit;
      end;
      
      var SubCountersAdded := self.SubCountersAdded;
      if SubCountersAdded<>nil then SubCountersAdded(0,1, count);
      
      var scale := 1/count;
      var sub_counter := new PersentDoneCounter(self, scale);
      
      var c_done := 0;
      sub_counter.SubCountersAdded += (pos, size, sub_count)->
      begin
        var SubCountersAdded := self.SubCountersAdded;
        if SubCountersAdded<>nil then SubCountersAdded((c_done+pos)*scale, size*scale, sub_count);
      end;
      
      loop count do
      begin
        proc(c_done, sub_counter);
        sub_counter.Reset;
        c_done += 1;
      end;
      
    end;
    public procedure SplitTasks<T>(inp_l: IList<T>; proc: (T, PersentDoneCounter)->()) :=
    SplitTasks(inp_l.Count, (ind, counter)->proc(inp_l[ind], counter));
    
  end;
  
end.