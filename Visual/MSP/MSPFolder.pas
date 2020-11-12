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
    
    protected function MakeMinimizable(dir: string): MinimizableList; override :=
    new MFolderContents(dir, expected_tr.SourceFName);
    
    protected property Description: string read 'File removal'; override;
    
  end;
  
end.