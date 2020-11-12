unit MSPStandard;

uses System.Windows;
uses System.Windows.Controls;
uses System.Windows.Media;

uses VUtils           in '..\VUtils';
uses DisplayListData  in '..\DisplayListData';
uses Counters         in '..\..\Backend\Counters';
uses MinimizableCore  in '..\..\Backend\MinimizableCore';

uses MSPCore;

type
  
  CounterContainer = sealed class(Grid)
    
    public constructor(c: Counter; descr: string);
    begin
      
      var pb := new SmoothProgressBar;
      self.Children.Add(pb);
      pb.SnapMax(1);
      c.ValueChanged += v->pb.Dispatcher.InvokeAsync(()->
      try
        pb.AnimateVal(v);
      except
        on e: Exception do
          MessageBox.Show(e.ToString);
      end);
      
      if not string.IsNullOrWhiteSpace(descr) then
      begin
        var tb := new TextBlock;
        self.Children.Add(tb);
        tb.HorizontalAlignment  := System.Windows.HorizontalAlignment.Center;
        tb.VerticalAlignment    := System.Windows.VerticalAlignment.Center;
        tb.Margin := new Thickness(5,2,5,2);
        tb.Text := descr;
      end;
      
    end;
    private constructor := raise new System.InvalidOperationException;
    
  end;
  
  VisualMSP = sealed class(Border)
    
    public constructor;
    begin
      self.BorderBrush := new SolidColorBrush(Colors.Black);
      self.BorderThickness := new Thickness(1);
      self.Padding := new Thickness(5);
    end;
    
    protected procedure SetCounter(main_counter: MinimizationCounter; descr: string);
    begin
      
      var sr := new SmoothResizer;
      self.Child := sr;
      
      var layer_counters_cont := new DisplayList;
      sr.Content := layer_counters_cont;
      layer_counters_cont.VerticalAlignment := System.Windows.VerticalAlignment.Top;
      layer_counters_cont.ChildrenShift := 15;
      
      var main_counter_container := new CounterContainer(main_counter, descr);
      layer_counters_cont.Header := main_counter_container;
      
      main_counter.LayerAdded += layer_counter->layer_counters_cont.Dispatcher.InvokeAsync(()->
      try
        var sr := new SmoothResizer;
        
        var dl := new DisplayList;
        sr.Content := dl;
        dl.Margin := new Thickness(0,5,0,0);
        dl.ChildrenShift := 10;
        dl.VerticalAlignment := System.Windows.VerticalAlignment.Top;
        dl.ShowChildren := false;
        
        var cc := new CounterContainer(layer_counter, $'by {layer_counter.LayerRemoveCount}');
        dl.Header := cc;
        
        var tb1 := new TextBlock;
        dl.Children.Add(tb1);
        tb1.Text := 'abc';
        
        var tb2 := new TextBlock;
        dl.Children.Add(tb2);
        tb2.Text := 'def';
        
        layer_counters_cont.Children.Add(sr, cc);
      except
        on e: Exception do
          MessageBox.Show(e.ToString);
      end);
      
    end;
    
  end;
  
  StandardMSP = abstract class(MinimizationStagePart)
    protected v: VisualMSP;
    
    protected property Description: string read; abstract;
    
    protected procedure OnCounterCreated(counter: MinimizationCounter); override :=
    self.v.Dispatcher.Invoke(()->v.SetCounter(counter, self.Description));
    
    public function MakeUIElement: System.Windows.UIElement; override;
    begin
      self.v := new VisualMSP;
      Result := v;
    end;
    
  end;
  
end.