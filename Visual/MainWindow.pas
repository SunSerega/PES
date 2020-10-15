unit MainWindow;

uses System.Windows;

uses PathUtils    in '..\Utils\PathUtils';

uses Testing      in '..\Backend\Testing';

uses Common;
uses BucketLoad;
uses Minimization;

type
  
  PESWindow = sealed class
    private w := new Window;
    
    public constructor;
    begin
      w.WindowStartupLocation := WindowStartupLocation.CenterScreen;
      
      w.Content := new BucketLoadViewer(tr->
      begin
        var inital_state_dir := $'{test_dir}\0';
        CopyDir(BucketDir, inital_state_dir);
        w.Content := new MinimizationViewer(inital_state_dir, tr);
      end);
      
    end;
    
    public static function operator implicit(w: PESWindow): Window := w.w;
    
  end;
  
end.