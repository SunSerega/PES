unit MSPFolder;

uses System.Windows;
uses System.Windows.Controls;
uses System.Windows.Media;

uses VUtils           in '..\VUtils';

uses MinimizableCore  in '..\..\Backend\MinimizableCore';
uses MFolder          in '..\..\Backend\Minimizables\MFolder';

uses MSPStandard;

type
  
  FolderMSP = sealed class(StandardMSP)
    
    protected function MakeMinimizable(dir, target: string): MinimizableContainer; override :=
    new MFolderContents(dir, target);
    
    protected property Description: string read 'File removal'; override;
    
    public function MakeTestUIElement(_m: MinimizableContainer; need_node: MinimizableNode->boolean): System.Windows.UIElement; override;
    begin
      var ToDo := 0;
      raise new System.NotImplementedException;
    end;
    
  end;
  
end.