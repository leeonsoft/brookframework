(*  _                     _
 * | |__  _ __ ___   ___ | | __
 * | '_ \| '__/ _ \ / _ \| |/ /
 * | |_) | | | (_) | (_) |   <
 * |_.__/|_|  \___/ \___/|_|\_\
 *
 * Microframework which helps to develop web Pascal applications.
 *
 * Copyright (c) 2012-2020 Silvio Clecio <silvioprog@gmail.com>
 *
 * Brook framework is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * Brook framework is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with Brook framework; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

unit BrookMathExpression;

{$I BrookDefines.inc}

interface

uses
  SysUtils,
  Classes,
  Math,
  Marshalling,
  libsagui,
  BrookHandledClasses;

resourcestring
  SBrookInactiveMathExpression = 'Inactive math expression.';

type
  (* experimental *)
  TBrookExpressionArguments = record
  private
    FHandle: Psg_expr_argument;
    function GetArgument(AIndex: Integer): Double;
    function GetHandle: Pointer;
  public
    constructor Create(AHandle: Psg_expr_argument);
    property Items[AIndex: Integer]: Double read GetArgument; default;
    property Handle: Pointer read GetHandle;
  end;

  (* experimental *)
  TBrookExpressionExtensionEvent = function(ASender: TObject;
    AArgs: TBrookExpressionArguments;
    const AIdentifier: string): Double of object;

  (* experimental *)
  TBrookExpressionErrorKind = (ekNone, ekUnknown, ekUnexpectedNumber,
    ekUnexpectedWord, ekUnexpectedParens, ekMissingOperand, ekUnknownOperator,
    ekInvalidFuncName, ekBadCall, ekBadParens, ekTooFewFuncArgs,
    ekFirstArgIsNotVar, ekBadVariableName, ekBadAssignment);

  (* experimental *)
  TBrookExpressionErrorEvent = procedure(ASender: TObject; ANear: Integer;
    AErrorKind: TBrookExpressionErrorKind; const AError: string) of object;

  (* experimental *)
  TBrookMathExpression = class(TBrookHandledComponent)
  private
    FExtensions: TStringList;
    FExtensionsHandle: array of sg_expr_extension;
    FOnExtension: TBrookExpressionExtensionEvent;
    FOnError: TBrookExpressionErrorEvent;
    FOnActivate: TNotifyEvent;
    FOnDeactivate: TNotifyEvent;
    FHandle: Psg_expr;
    FExpression: string;
    FActive: Boolean;
    FStreamedActive: Boolean;
    FCompiled: Boolean;
    function IsActiveStored: Boolean;
    procedure SetActive(AValue: Boolean);
    procedure SetExtensions(AValue: TStringList);
    procedure SetExpression(const AValue: string);
    procedure InternalLibUnloadEvent(ASender: TObject);
  protected
    function CreateExtensions: TStringList; virtual;
    class function DoExprFunc(Acls: Pcvoid; Aargs: Psg_expr_argument;
      const Aidentifier: Pcchar): cdouble; cdecl; static;
    procedure Loaded; override;
    function GetHandle: Pointer; override;
    function DoExtension(ASender: TObject; AArgs: TBrookExpressionArguments;
      const AIdentifier: string): Double; virtual;
    procedure DoError(ASender: TObject; ANear: Integer;
      AErrorKind: TBrookExpressionErrorKind; const AError: string); virtual;
    procedure DoOpen; virtual;
    procedure DoClose; virtual;
    procedure CheckActive; inline;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Open;
    procedure Close;
    function Compile(const AExpression: string; out ANear: Integer;
      out AErrorKind: TBrookExpressionErrorKind): Boolean; overload; virtual;
    function Compile(const AExpression: string): Boolean; overload; virtual;
    procedure Clear; virtual;
    function Evaluate: Double; virtual;
    function GetVariable(const AName: string): Double; virtual;
    procedure SetVariable(const AName: string; const AValue: Double); virtual;
    property Compiled: Boolean read FCompiled;
    property Variables[const AName: string]: Double read GetVariable
      write SetVariable; default;
  published
    property Active: Boolean read FActive write SetActive stored IsActiveStored;
    property Expression: string read FExpression write SetExpression;
    property Extensions: TStringList read FExtensions write SetExtensions;
    property OnExtension: TBrookExpressionExtensionEvent read FOnExtension
      write FOnExtension;
    property OnError: TBrookExpressionErrorEvent read FOnError write FOnError;
    property OnActivate: TNotifyEvent read FOnActivate write FOnActivate;
    property OnDeactivate: TNotifyEvent read FOnDeactivate write FOnDeactivate;
  end;

implementation

{ TBrookExpressionArguments }

constructor TBrookExpressionArguments.Create(AHandle: Psg_expr_argument);
begin
  FHandle := AHandle;
end;

function TBrookExpressionArguments.GetHandle: Pointer;
begin
  Result := FHandle;
end;

function TBrookExpressionArguments.GetArgument(AIndex: Integer): Double;
begin
  SgLib.Check;
  Result := sg_expr_arg(FHandle, AIndex);
end;

{ TBrookMathExpression }

constructor TBrookMathExpression.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FExtensions := CreateExtensions;
  SgLib.AddUnloadEvent(InternalLibUnloadEvent, Self);
end;

destructor TBrookMathExpression.Destroy;
begin
  SetActive(False);
  FExtensions.Free;
  SgLib.RemoveUnloadEvent(InternalLibUnloadEvent);
  inherited Destroy;
end;

class function TBrookMathExpression.DoExprFunc(Acls: Pcvoid;
  Aargs: Psg_expr_argument; const Aidentifier: Pcchar): cdouble;
begin
  Result := TBrookMathExpression(Acls).DoExtension(Acls,
    TBrookExpressionArguments.Create(Aargs), TMarshal.ToString(Aidentifier));
end;

function TBrookMathExpression.CreateExtensions: TStringList;
begin
  Result := TStringList.Create;
end;

procedure TBrookMathExpression.CheckActive;
begin
  if (not (csLoading in ComponentState)) and (not Active) then
    raise EInvalidOpException.Create(SBrookInactiveMathExpression);
end;

procedure TBrookMathExpression.Loaded;
begin
  inherited Loaded;
  try
    if FStreamedActive then
      SetActive(True);
  except
    if csDesigning in ComponentState then
    begin
      if Assigned(ApplicationHandleException) then
        ApplicationHandleException(ExceptObject)
      else
        ShowException(ExceptObject, ExceptAddr);
    end
    else
      raise;
  end;
end;

function TBrookMathExpression.GetHandle: Pointer;
begin
  Result := FHandle;
end;

procedure TBrookMathExpression.InternalLibUnloadEvent(ASender: TObject);
begin
  TBrookMathExpression(ASender).Close;
end;

function TBrookMathExpression.DoExtension(ASender: TObject;
  AArgs: TBrookExpressionArguments; const AIdentifier: string): Double;
begin
  if Assigned(FOnExtension) then
    Exit(FOnExtension(ASender, AArgs, AIdentifier));
  Result := NaN;
end;

procedure TBrookMathExpression.DoError(ASender: TObject; ANear: Integer;
  AErrorKind: TBrookExpressionErrorKind; const AError: string);
begin
  if Assigned(FOnError) then
    FOnError(ASender, ANear, AErrorKind, AError);
end;

procedure TBrookMathExpression.SetExpression(const AValue: string);
begin
  if AValue = FExpression then
    Exit;
  FExpression := AValue;
  Clear;
end;

procedure TBrookMathExpression.SetExtensions(AValue: TStringList);
begin
  if Assigned(AValue) then
    FExtensions.Assign(AValue)
  else
    FExtensions.Clear;
end;

procedure TBrookMathExpression.DoOpen;
begin
  if Assigned(FHandle) then
    Exit;
  SgLib.Check;
  FHandle := sg_expr_new;
  FActive := Assigned(FHandle);
  if Assigned(FOnActivate) then
    FOnActivate(Self);
end;

procedure TBrookMathExpression.DoClose;
begin
  FExtensionsHandle := nil;
  if not Assigned(FHandle) then
    Exit;
  SgLib.Check;
  sg_expr_free(FHandle);
  FHandle := nil;
  FActive := False;
  FCompiled := False;
  if Assigned(FOnDeactivate) then
    FOnDeactivate(Self);
end;

function TBrookMathExpression.IsActiveStored: Boolean;
begin
  Result := FActive;
end;

procedure TBrookMathExpression.SetActive(AValue: Boolean);
begin
  if AValue = FActive then
    Exit;
  if csDesigning in ComponentState then
  begin
    if not (csLoading in ComponentState) then
      SgLib.Check;
    FActive := AValue;
  end
  else
    if AValue then
    begin
      if csReading in ComponentState then
        FStreamedActive := True
      else
        DoOpen;
    end
    else
      DoClose;
end;

function TBrookMathExpression.GetVariable(const AName: string): Double;
var
  M: TMarshaller;
begin
  CheckActive;
  SgLib.Check;
  Result := sg_expr_var(FHandle, M.ToCString(AName), Length(AName));
end;

procedure TBrookMathExpression.SetVariable(const AName: string;
  const AValue: Double);
var
  M: TMarshaller;
begin
  CheckActive;
  SgLib.Check;
  SgLib.CheckLastError(sg_expr_set_var(FHandle, M.ToCString(AName),
    Length(AName), AValue));
end;

function TBrookMathExpression.Compile(const AExpression: string;
  out ANear: Integer; out AErrorKind: TBrookExpressionErrorKind): Boolean;
var
  EX: sg_expr_extension;
  M: TMarshaller;
  I: Integer;
  R: cint;
begin
  if FCompiled then
    Exit(True);
  CheckActive;
  SgLib.Check;
  SetLength(FExtensionsHandle, Succ(FExtensions.Count));
  for I := 0 to Pred(FExtensions.Count) do
  begin
    EX.func := DoExprFunc;
    EX.identifier := M.ToCString(FExtensions[I]);
    EX.cls := Self;
    FExtensionsHandle[I] := EX;
  end;
  FExtensionsHandle[FExtensions.Count] := Default(sg_expr_extension);
  R := sg_expr_compile(FHandle, M.ToCString(AExpression), Length(AExpression),
    @FExtensionsHandle[0]);
  FCompiled := R = 0;
  if not FCompiled then
  begin

    ANear := sg_expr_near(FHandle);
    AErrorKind := TBrookExpressionErrorKind(sg_expr_err(FHandle));
  end;
  Result := FCompiled;
end;

function TBrookMathExpression.Compile(const AExpression: string): Boolean;
var
  N: Integer;
  E: TBrookExpressionErrorKind;
begin
  Result := Compile(AExpression, N, E);
  if not Result then
    DoError(Self, N, E, TMarshal.ToString(sg_expr_strerror(FHandle)));
end;

procedure TBrookMathExpression.Clear;
begin
  if not Assigned(FHandle) then
    Exit;
  SgLib.Check;
  SgLib.CheckLastError(sg_expr_clear(FHandle));
  FExtensionsHandle := nil;
  FCompiled := False;
end;

function TBrookMathExpression.Evaluate: Double;
begin
  if FCompiled then
  begin
    CheckActive;
    SgLib.Check;
  end
  else
    Compile(FExpression);
  Result := sg_expr_eval(FHandle);
end;

procedure TBrookMathExpression.Open;
begin
  SetActive(True);
end;

procedure TBrookMathExpression.Close;
begin
  SetActive(False);
end;

end.