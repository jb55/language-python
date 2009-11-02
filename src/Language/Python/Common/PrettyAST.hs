-----------------------------------------------------------------------------
-- |
-- Module      : Language.Python.Version2.Syntax.PrettyAST
-- Copyright   : (c) 2009 Bernie Pope 
-- License     : BSD-style
-- Maintainer  : bjpop@csse.unimelb.edu.au
-- Stability   : experimental
-- Portability : ghc
--
-- Pretty printing of the Python abstract syntax (version 2 and 3). 
-----------------------------------------------------------------------------

module Language.Python.Common.PrettyAST where

import Language.Python.Common.Pretty
import Language.Python.Common.AST 
import qualified Data.ByteString.Char8 as BS

--------------------------------------------------------------------------------

dot :: Doc
dot = char '.'

indent :: Doc -> Doc
indent doc = nest 4 doc

-- XXX is there a better way to do this?
blankLine :: Doc
blankLine = text []

instance Pretty BS.ByteString where
   -- XXX should handle the escaping properly
   pretty b = text "b" <> text (show $ BS.unpack b)

prettyString :: String -> Doc
   -- XXX should handle the escaping properly
prettyString str = text (show str)

instance Pretty (Module a) where
   pretty (Module stmts) = vcat $ map pretty stmts 

instance Pretty (Ident a) where
   pretty name@(Ident {}) = text $ ident_string name

prettyDottedName :: DottedName a -> Doc
prettyDottedName [] = empty
prettyDottedName [name] = pretty name
prettyDottedName (name:rest@(_:_))
   = pretty name <> dot <> prettyDottedName rest

instance Pretty (ImportItem a) where
   pretty (ImportItem {import_item_name = name, import_as_name = asName})
      = prettyDottedName name <+> (maybe empty (\n -> text "as" <+> pretty n) asName)

instance Pretty (FromItem a) where
   pretty (FromItem { from_item_name = name, from_as_name = asName })
      = pretty name <+> (maybe empty (\n -> text "as" <+> pretty n) asName) 

instance Pretty (FromItems a) where
   pretty ImportEverything {} = char '*'
   pretty (FromItems { from_items_items = [item] }) = pretty item 
   pretty (FromItems { from_items_items = items }) = parens (commaList items)

instance Pretty (ImportRelative a) where
   pretty (ImportRelative { import_relative_dots = dots, import_relative_module = mod }) 
      = case mod of
           Nothing -> dotDoc 
           Just name -> dotDoc <> prettyDottedName name 
      where
      dotDoc = text (replicate dots '.')

prettySuite :: [Statement a] -> Doc
prettySuite stmts = vcat $ map pretty stmts 

optionalKeywordSuite :: String -> [Statement a] -> Doc
optionalKeywordSuite _ [] = empty
optionalKeywordSuite keyword stmts = text keyword <> colon $+$ indent (prettySuite stmts)

prettyArgList :: [Argument a] -> Doc
prettyArgList = parens . commaList 

prettyOptionalList :: Pretty a => [a] -> Doc
prettyOptionalList [] = empty
prettyOptionalList list = parens $ commaList list

prettyGuards :: [(Expr a, Suite a)] -> Doc
prettyGuards [] = empty
prettyGuards ((cond,body):guards)
   = text "elif" <+> pretty cond <> colon $+$ indent (prettySuite body) $+$
     prettyGuards guards

instance Pretty (Statement a) where
   -- pretty :: Statement -> Doc 
   pretty (Import { import_items = items}) = text "import" <+> commaList items 
   pretty stmt@(FromImport {})
      = text "from" <+> pretty (from_module stmt) <+> text "import" <+> pretty (from_items stmt)
   pretty stmt@(While {})
      = text "while" <+> pretty (while_cond stmt) <> colon $+$
        indent (prettySuite (while_body stmt)) $+$ optionalKeywordSuite "else" (while_else stmt)
   pretty stmt@(For {})
      = text "for" <+> commaList (for_targets stmt) <+> text "in" <+> pretty (for_generator stmt) <> colon $+$
        indent (prettySuite (for_body stmt)) $+$ optionalKeywordSuite "else" (for_else stmt)
   pretty stmt@(Fun {})
      = text "def" <+> pretty (fun_name stmt) <> parens (commaList (fun_args stmt)) <+> 
        perhaps (fun_result_annotation stmt) (text "->") <+>
        pretty (fun_result_annotation stmt) <> colon $+$ indent (prettySuite (fun_body stmt)) 
   pretty stmt@(Class {})
      = text "class" <+> pretty (class_name stmt) <> prettyOptionalList (class_args stmt) <> 
        colon $+$ indent (prettySuite (class_body stmt)) 
   pretty stmt@(Conditional { cond_guards = guards, cond_else = optionalElse })
      = case guards of
           (cond,body):xs -> 
              text "if" <+> pretty cond <> colon $+$ indent (prettySuite body) $+$ 
              prettyGuards xs $+$
              optionalKeywordSuite "else" optionalElse
   -- XXX is the assign_to always a singleton?
   pretty (Assign { assign_to = pattern, assign_expr = e })
      = commaList pattern <+> equals <+> pretty e
   pretty (AugmentedAssign { aug_assign_to = to_expr, aug_assign_op = op, aug_assign_expr = e})
      = pretty to_expr <+> pretty op <+> pretty e 
   pretty (Decorated { decorated_decorators = decs, decorated_def = stmt})
      = vcat (map pretty decs) $+$ pretty stmt
   pretty (Return { return_expr = e }) = text "return" <+> pretty e
   pretty (Try { try_body = body, try_excepts = handlers, try_else = optionalElse, try_finally = finally})
      = text "try" <> colon $+$ indent (prettySuite body) $+$
        prettyHandlers handlers $+$ optionalKeywordSuite "else" optionalElse $+$ 
        optionalKeywordSuite "finally" finally 
   pretty (Raise { raise_expr = e })
      = text "raise" <+> pretty e
   pretty (With { with_context = context, with_body = body })
      = text "with" <+> hcat (punctuate comma (map prettyWithContext context)) <+> colon $+$
        indent (prettySuite body)
   pretty Pass {} = text "pass"
   pretty Break {} = text "break"
   pretty Continue {} = text "continue"
   pretty (Delete { del_exprs = es }) = text "del" <+> commaList es
   pretty (StmtExpr { stmt_expr = e }) = pretty e
   pretty (Global { global_vars = idents }) = text "global" <+> commaList idents
   pretty (NonLocal { nonLocal_vars = idents }) = text "nonlocal" <+> commaList idents
   pretty (Assert { assert_exprs = es }) = text "assert" <+> commaList es
   pretty (Print { print_chevron = have_chevron, print_exprs = es, print_trailing_comma = trail_comma }) =
      text "print" <> (if have_chevron then text " >>>" else empty) <+>
      hcat (punctuate comma (map pretty es)) <>
      if trail_comma then comma else empty
   pretty (Exec { exec_expr = e, exec_globals_locals = gls }) = 
      text "exec" <+> pretty e <+> 
      maybe empty (\ (globals, next) -> text "in" <+> pretty globals <+>
      maybe empty (\locals -> comma <+> pretty locals) next) gls

prettyWithContext :: (Expr a, Maybe (Expr a)) -> Doc
prettyWithContext (e, Nothing) = pretty e
prettyWithContext (e, Just as) = pretty e <+> text "as" <+> pretty as

prettyHandlers :: [Handler a] -> Doc
prettyHandlers = foldr (\next rec -> pretty next $+$ rec) empty


instance Pretty (Handler a) where
   pretty (Handler { handler_clause = exceptClause, handler_suite = suite })
      = pretty exceptClause <> colon $+$ indent (prettySuite suite)

instance Pretty (ExceptClause a) where
   pretty (ExceptClause { except_clause = Nothing }) = text "except"
   pretty (ExceptClause { except_clause = Just (e, target)}) 
      = text "except" <+> pretty e <+> maybe empty (\t -> text "as" <+> pretty t) target

instance Pretty (RaiseExpr a) where
   pretty (RaiseV3 e) = 
      maybe empty (\ (x, fromE) -> pretty x <+> (maybe empty (\f -> text "from" <+> pretty f) fromE)) e
   pretty (RaiseV2 exp) = 
      maybe empty (\ (e1, next1) -> pretty e1 <> comma <+>
      maybe empty (\ (e2, next2) -> pretty e2 <> comma <+>
      maybe empty (\ e3 -> pretty e3) next2) next1) exp

instance Pretty (Decorator a) where
   pretty (Decorator { decorator_name = name, decorator_args = args })
      = char '@' <> prettyDottedName name <+> prettyOptionalList args

instance Pretty (Parameter a) where
   pretty (Param { param_name = ident, param_py_annotation = annot, param_default = def})
      = pretty ident <> (maybe empty (\e -> colon <> pretty e <> space) annot) <> 
        maybe empty (\e -> equals <> pretty e) def 
   pretty (VarArgsPos { param_name = ident, param_py_annotation = annot})
      = char '*' <> pretty ident <> (maybe empty (\e -> colon <> pretty e) annot)
   pretty (VarArgsKeyword { param_name = ident, param_py_annotation = annot })
      = text "**" <> pretty ident <> (maybe empty (\e -> colon <> pretty e) annot)
   pretty EndPositional {} = char '*' 

instance Pretty (Argument a) where
   pretty (ArgExpr { arg_expr = e }) = pretty e
   pretty (ArgVarArgsPos { arg_expr = e}) = char '*' <> pretty e
   pretty (ArgVarArgsKeyword { arg_expr = e }) = text "**" <> pretty e
   pretty (ArgKeyword { arg_keyword = ident, arg_expr = e }) 
      = pretty ident <> equals <> pretty e

instance Pretty t => Pretty (Comprehension t a) where
   pretty (Comprehension { comprehension_expr = e, comprehension_for = for }) 
      = pretty e <+> pretty for 

instance Pretty (CompFor a) where
   pretty (CompFor { comp_for_exprs = es, comp_in_expr = e, comp_for_iter = iter }) 
      = text "for" <+> commaList es <+> text "in" <+> pretty e <+> pretty iter

instance Pretty (CompIf a) where
   pretty (CompIf { comp_if = e, comp_if_iter = iter }) 
      = text "if" <+> pretty e <+> pretty iter 

instance Pretty (CompIter a) where
   pretty (IterFor { comp_iter_for = compFor }) = pretty compFor 
   pretty (IterIf { comp_iter_if = compIf }) = pretty compIf

instance Pretty (Expr a) where
   pretty (Var { var_ident = i }) = pretty i
   pretty (Int { int_value = i }) = pretty i
   pretty (Float { float_value = d }) = pretty d
   pretty (Imaginary { imaginary_value = i }) = pretty i <> char 'j' 
   pretty (Bool { bool_value = b}) = pretty b
   pretty None {} = text "None"
   pretty Ellipsis {} = text "..."
   pretty (ByteStrings { byte_string_strings = bs }) = hcat (map pretty bs)
   pretty (Strings { strings_strings = ss }) = hcat (map prettyString ss)
   pretty (Call { call_fun = f, call_args = args }) = pretty f <> prettyArgList args
   pretty (Subscript { subscriptee = e, subscript_exprs = subs })
      = pretty e <> brackets (commaList subs)
   pretty (SlicedExpr { slicee = e, slices = ss })
      = pretty e <> brackets (commaList ss) 
   pretty (CondExpr { ce_true_branch = trueBranch, ce_condition = cond, ce_false_branch = falseBranch })
      = pretty trueBranch <+> text "if" <+> pretty cond <+> text "else" <+> pretty falseBranch
   pretty (BinaryOp { operator = op, left_op_arg = left, right_op_arg = right })
      = pretty left <> (if isDot op then dot else space <> pretty op <> space) <> pretty right
      where
      isDot (Dot {}) = True
      isDot _other = False
   pretty (UnaryOp { operator = op, op_arg = e }) = pretty op <+> pretty e
   pretty (Lambda { lambda_args = args, lambda_body = body })
      = text "lambda" <+> commaList args <> colon <+> pretty body
   pretty (Tuple { tuple_exprs = es }) = commaList es
   pretty (Yield { yield_expr = e })
      = text "yield" <+> pretty e
   pretty (List { list_exprs = es }) = brackets (commaList es)
   pretty (Dictionary { dict_mappings = mappings })
      = braces (hsep (punctuate comma $ map (\ (e1,e2) -> pretty e1 <> colon <> pretty e2) mappings))
   pretty (Set { set_exprs = es }) = braces $ commaList es
   pretty (ListComp { list_comprehension = lc }) = brackets $ pretty lc
   pretty (Generator { gen_comprehension = gc }) = parens $ pretty gc
   pretty (Paren { paren_expr = e }) = parens $ pretty e

instance Pretty (Slice a) where
   pretty (SliceProper { slice_lower = lower, slice_upper = upper, slice_stride = stride })
      = pretty lower <> colon <> pretty upper <> (maybe empty (\s -> colon <> pretty s) stride)
   pretty (SliceExpr { slice_expr = e }) = pretty e

instance Pretty (Op a) where
   pretty (And {}) = text "and"
   pretty (Or {}) = text "or"
   pretty (Not {}) = text "not"
   pretty (Exponent {}) = text "**"
   pretty (LessThan {}) = text "<"
   pretty (GreaterThan {}) = text ">"
   pretty (Equality {}) = text "=="
   pretty (GreaterThanEquals {}) = text ">="
   pretty (LessThanEquals {}) = text "<="
   pretty (NotEquals {}) = text "!="
   pretty (NotEqualsV2 {}) = text "<>"
   pretty (In {}) = text "in"
   pretty (Is {}) = text "is"
   pretty (IsNot {}) = text "is not"
   pretty (NotIn {}) = text "not in"
   pretty (BinaryOr {}) = text "|"
   pretty (Xor {}) = text "^"
   pretty (BinaryAnd {}) = text "&"
   pretty (ShiftLeft {}) = text "<<"
   pretty (ShiftRight {}) = text ">>"
   pretty (Multiply {}) = text "*"
   pretty (Plus {}) = text "+"
   pretty (Minus {}) = text "-"
   pretty (Divide {}) = text "/"
   pretty (FloorDivide {}) = text "//"
   pretty (Invert {}) = text "~"
   pretty (Modulo {}) = text "%"
   pretty (Dot {}) = dot

instance Pretty (AssignOp a) where
   pretty (PlusAssign {}) = text "+="
   pretty (MinusAssign {}) = text "-="
   pretty (MultAssign {}) = text "*="
   pretty (DivAssign {}) = text "/="
   pretty (ModAssign {}) = text "%="
   pretty (PowAssign {}) = text "**="
   pretty (BinAndAssign {}) = text "&="
   pretty (BinOrAssign {}) = text "|="
   pretty (BinXorAssign {}) = text "^="
   pretty (LeftShiftAssign {}) = text "<<="
   pretty (RightShiftAssign {}) = text ">>="
   pretty (FloorDivAssign {}) = text "//="