unit Common;

uses System.Windows;
uses System.Windows.Controls;
uses System.Windows.Media;

uses PathUtils    in '..\Utils\PathUtils';

uses Testing      in '..\Backend\Testing';
uses SettingData  in '..\Backend\SettingData';

uses VUtils;

var test_dir := $'Log\{DateTime.Now.Ticks}';

type
  
  /// Кнопка запуска теста с конкретными настройками
  TestResultViewer = sealed class(Button)
    
    public constructor(tr: TestResult; when_selected: TestResult->());
    begin
      self.Margin := new Thickness(5,5,5,0);
      self.HorizontalContentAlignment := System.Windows.HorizontalAlignment.Left;
      self.HorizontalAlignment := System.Windows.HorizontalAlignment.Left;
      
      var sp := new StackPanel;
      self.Content := sp;
      sp.Orientation := Orientation.Horizontal;
      
      var icon := new Image;
      sp.Children.Add(icon);
      icon.Width  := 16;
      icon.Height := 16;
      icon.Margin := new Thickness(3,0,0,0);
      
      var description := new TextBlock;
      sp.Children.Add(description);
      description.Text := tr.GetShortDescription;
      description.Margin := new Thickness(3);
      
      match tr with
        
        CompResult(ctr):
        begin
          {$resource '..\Resources\CompTest.png'}
          CachedImageSource['CompTest.png'].Apply(icon);
        end;
        
        ExecResult(etr):
        begin
          {$resource '..\Resources\ExecTest.png'}
          CachedImageSource['ExecTest.png'].Apply(icon);
        end;
        
        else raise new System.NotSupportedException;
      end;
      
      if when_selected <> nil then
        self.Click += (o,e)->when_selected(tr);
    end;
    
  end;
  
end.