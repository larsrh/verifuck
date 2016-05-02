theory Verifuck
imports
  Main
  "~~/src/HOL/Word/Word"
  "~~/src/HOL/Library/Code_Char"
begin

datatype instr = Incr | Decr | Right | Left | Out | In | Loop | Pool

fun parse_instrs :: "string \<Rightarrow> instr list" where
"parse_instrs [] = []" |
"parse_instrs (x # xs) = (
  if x = CHR ''.'' then Out # parse_instrs xs else
  if x = CHR '','' then In # parse_instrs xs else
  if x = CHR ''+'' then Incr # parse_instrs xs else
  if x = CHR ''-'' then Decr # parse_instrs xs else
  if x = CHR ''<'' then Left # parse_instrs xs else
  if x = CHR ''>'' then Right # parse_instrs xs else
  if x = CHR ''['' then Loop # parse_instrs xs else
  if x = CHR '']'' then Pool # parse_instrs xs else
  parse_instrs xs)"

datatype 'a tape = Tape (left: "'a list") (cur: 'a) (right: "'a list")

definition empty_tape :: "'a::zero tape" where
"empty_tape = Tape [] 0 []"

definition tape_map_cur :: "('a \<Rightarrow> 'a) \<Rightarrow> 'a tape \<Rightarrow> 'a tape" where
[simp]: "tape_map_cur f tape = Tape (left tape) (f (cur tape)) (right tape)"

fun tape_shift_right :: "'a::zero tape \<Rightarrow> 'a tape" where
"tape_shift_right (Tape l c []) = Tape (c # l) 0 []" |
"tape_shift_right (Tape l c (r # rs)) = Tape (c # l) r rs"

fun tape_shift_left :: "'a::zero tape \<Rightarrow> 'a tape" where
"tape_shift_left (Tape [] c r) = Tape [] 0 (c # r)" |
"tape_shift_left (Tape (l # ls) c r) = Tape ls l (c # r)"

datatype ('a, 'b) io = Buffer (state: 'b) (read: "'b \<Rightarrow> ('a \<times> 'b)") (out_buf: "'a list")

type_synonym ('a, 'b) machine = "'a tape \<times> ('a, 'b) io"

definition read_io :: "('a, 'b) io \<Rightarrow> ('a \<times> ('a, 'b) io)" where
[simp]: "read_io io = (let (c, state') = read io (state io) in (c, Buffer state' (read io) (out_buf io)))"

definition write_io :: "'a \<Rightarrow> ('a, 'b) io \<Rightarrow> ('a, 'b) io" where
[simp]: "write_io c io = Buffer (state io) (read io) (c # out_buf io)"

type_synonym instr_table = "instr list \<times> instr list list"

definition init_table :: "instr list \<Rightarrow> instr_table" where
"init_table xs = (xs, [])"

fun next_machine :: "instr \<Rightarrow> ('a::{zero,one,minus,plus}, 'b) machine \<Rightarrow> ('a, 'b) machine" where
"next_machine Incr = apfst (tape_map_cur (\<lambda>x. x + 1))" |
"next_machine Decr = apfst (tape_map_cur (\<lambda>x. x - 1))" |
"next_machine Left = apfst tape_shift_left" |
"next_machine Right = apfst tape_shift_right" |
"next_machine In = (\<lambda>(tape, io). let (c, io') = read_io io in (tape_map_cur (\<lambda>_. c) tape, io'))" |
"next_machine Out = (\<lambda>(tape, io). (tape, write_io (cur tape) io))"

(*TODO: needs documentation*)
fun skip_loop :: "instr list \<Rightarrow> nat \<Rightarrow> instr list" where
"skip_loop xs 0 = xs" |
"skip_loop (Loop # xs) n = skip_loop xs (n + 1)" |
"skip_loop (Pool # xs) n = skip_loop xs (n - 1)" |
"skip_loop (x # xs) n = skip_loop xs n" |
"skip_loop [] n = []"

partial_function (tailrec) interp_bf :: "instr_table \<Rightarrow> ('a::{zero,one,minus,plus}, 'b) machine \<Rightarrow> ('a, 'b) machine" where
"interp_bf tab m =
  (case tab of ([], _) \<Rightarrow> m |
               (Loop # is, stack) \<Rightarrow> if cur (fst m) = 0 then interp_bf (skip_loop is 1, stack) m else interp_bf (is, (Loop # is) # stack) m |
               (Pool # _, is # stack) \<Rightarrow> interp_bf (is, stack) m |
               (Pool # _, []) \<Rightarrow> m |
               (i # is, stack) \<Rightarrow> interp_bf (is, stack) (next_machine i m))"

declare interp_bf.simps[code]

(*undefined behavior if reading from undefined input buffer. Pretty unusable since we cannot
  query from within our bf-code whether there is something to read available.*)
definition run_bf_generic :: "instr list \<Rightarrow> 'a::{zero,one,minus,plus} list \<Rightarrow> 'a list" where
"run_bf_generic prog input = rev (out_buf (snd (interp_bf (init_table prog)
                                  (empty_tape, (Buffer input (case_list undefined Pair) [])))))"


(*https://en.wikipedia.org/wiki/Brainfuck#End-of-file_behavior*)
definition EOF :: "8 word" where
  "EOF \<equiv> 255"
fun read_byte :: "8 word list \<Rightarrow> (8 word \<times> 8 word list)" where
  "read_byte [] = (EOF, [])" |
  "read_byte (b#bs) = (b, bs)"

definition run_bf :: "instr list \<Rightarrow> 8 word list \<Rightarrow> 8 word list" where
"run_bf prog input = rev (out_buf (snd (interp_bf (init_table prog)
                                  (empty_tape, (Buffer input read_byte [])))))"

export_code run_bf in SML module_name Verifuck file "code/verifuck.ML"
(*SML_file "code/verifuck.ML"*)

(*source: http://de.wikipedia.org/wiki/Brainfuck#Hello_World.21 retrieved Feb 7 2015*)
definition "hello_world = ''++++++++++
 [
  >+++++++>++++++++++>+++>+<<<<-
 ]                       Schleife zur Vorbereitung der Textausgabe
 >++.                    Ausgabe von 'H'
 >+.                     Ausgabe von 'e'
 +++++++.                'l'
 .                       'l'
 +++.                    'o'
 >++.                    Leerzeichen
 <<+++++++++++++++.      'W'
 >.                      'o'
 +++.                    'r'
 ------.                 'l'
 --------.               'd'
 >+.                     '!'
 >.                      Zeilenvorschub
 +++.                    Wagenruecklauf''"

definition byte_to_char :: "8 word \<Rightarrow> char" where
  "byte_to_char b \<equiv> char_of_nat (unat b)"
definition char_to_byte :: "char \<Rightarrow> 8 word" where
  "char_to_byte c \<equiv> of_nat (nat_of_char c)"

lemma "let result = run_bf (parse_instrs hello_world) ([]::8 word list) in
         map byte_to_char result = ''Hello World!'' @ [CHR ''\<newline>'', Char Nibble0 NibbleD]" by eval

export_code run_bf in Haskell










fun skip_loop_forward :: "instr list \<Rightarrow> instr list \<Rightarrow> nat \<Rightarrow> (instr list \<times> instr list)" where
"skip_loop_forward [] rs _ = ([], rs)" |
"skip_loop_forward (Pool # cs) rs 0 = (cs, Pool#rs)" |
"skip_loop_forward (Pool # cs) rs (Suc n) = skip_loop_forward cs (Pool#rs) n" |
"skip_loop_forward (Loop # cs) rs n = skip_loop_forward cs (Loop#rs) (n + 1)"  |
"skip_loop_forward (c # cs) rs n = skip_loop_forward cs (c#rs) n"

fun skip_loop_backward :: "instr list \<Rightarrow> instr list \<Rightarrow> nat \<Rightarrow> (instr list \<times> instr list)" where
"skip_loop_backward cs [] _ = (cs, [])" |
"skip_loop_backward cs (Loop # rs) 0 = (Loop#cs, rs)" |
"skip_loop_backward cs (Loop # rs) (Suc n) = skip_loop_backward (Loop#cs) rs n" |
"skip_loop_backward cs (Pool # rs) n = skip_loop_backward (Loop#cs) rs (n + 1)"  |
"skip_loop_backward cs (c#rs) n = skip_loop_backward (c#cs) rs n" 



(*steps left \<Rightarrow> current program \<Rightarrow> executed instructions \<Rightarrow> skip because we are in a loop? \<Rightarrow> ...*)
fun  bounded_machine :: "nat \<Rightarrow> instr list \<Rightarrow> instr list \<Rightarrow> 
                          ('a::{zero,one,minus,plus}, 'b) machine \<Rightarrow> ('a, 'b) machine option" where
"bounded_machine 0 _ _ m  = None" | (*TODO: error out-of-instructions*)
"bounded_machine _ [] _ m  = Some m" |
"bounded_machine (Suc n) (Incr#cs) rs m = bounded_machine n cs (Incr#rs) (apfst (tape_map_cur (\<lambda>x. x + 1)) m)" |
"bounded_machine (Suc n) (Decr#cs) rs m = bounded_machine n cs (Decr#rs) (apfst (tape_map_cur (\<lambda>x. x - 1)) m)" |
"bounded_machine (Suc n) (Left#cs) rs m = bounded_machine n cs (Left#rs) (apfst tape_shift_left m)" |
"bounded_machine (Suc n) (Right#cs) rs m = bounded_machine n cs (Right#rs) (apfst tape_shift_right m)" |
"bounded_machine (Suc n) (In#cs) rs m = bounded_machine n cs (In#rs)
                                            ((\<lambda>(tape, io). let (c, io') = read_io io in (tape_map_cur (\<lambda>_. c) tape, io')) m)" |
"bounded_machine (Suc n) (Out#cs) rs m = bounded_machine n cs (Out#rs)
                                            ((\<lambda>(tape, io). (tape, write_io (cur tape) io)) m)" |
"bounded_machine (Suc n) (Loop#cs) rs m = (if cur (fst m) = 0 then 
                                           (let (cs', rs') = skip_loop_forward cs (Loop#rs) 0 in 
                                            bounded_machine n cs' rs' m)
                                          else bounded_machine n cs (Loop#rs) m)" |
"bounded_machine (Suc n) (Pool#cs) rs m = (let (cs', rs') = skip_loop_backward (Pool#cs) rs 0 in 
                                            bounded_machine n cs' rs' m)"

value "bounded_machine 40 [Incr, Loop, Incr, Pool] [] (empty_tape, Buffer [] read_byte [])"


value "bounded_machine 40000 [Decr, Loop, Loop, Decr, Right, Incr, Left, Pool, Out, Decr, Pool] [] (empty_tape, Buffer [] read_byte [])"

definition run_bf_bounded :: "nat \<Rightarrow> instr list \<Rightarrow> 8 word list \<Rightarrow> 8 word list" where
"run_bf_bounded limit prog input \<equiv> case bounded_machine limit prog [] (empty_tape, Buffer input read_byte [])
    of Some (tape, buf) \<Rightarrow> rev (out_buf buf)"


lemma "let result = run_bf_bounded 1024 (parse_instrs hello_world) [] in
         map byte_to_char result = ''Hello World!'' @ [CHR ''\<newline>'', Char Nibble0 NibbleD]" by eval

end
