From RecordUpdate Require Import RecordSet.

From Perennial.goose_lang Require Import crash_modality.
From Perennial.algebra Require Import deletable_heap.

From Goose.github_com.mit_pdos.perennial_examples Require Import single_inode.
From Perennial.goose_lang.lib Require Import lock.crash_lock.
From Perennial.program_proof Require Import disk_lib.
From Perennial.program_proof.examples Require Import
     range_set alloc_crash_proof inode_proof.
From Perennial.program_proof Require Import proof_prelude.

Module s_inode.
  Definition t := list Block.
End s_inode.

(* discrete ofe over lists *)
Canonical Structure listLO A := leibnizO (list A).

Section goose.
  Context `{!heapG Σ}.
  Context `{!lockG Σ}.
  Context `{!crashG Σ}.
  Context `{!allocG Σ}.
  Context `{!stagedG Σ}.
  Context `{!inG Σ (ghostR (listLO Block))}.

  Implicit Types (l:loc) (σ: s_inode.t) (γ: gname).

  Let N := nroot.@"single_inode".
  Let allocN := nroot.@"allocator".
  Context (P: s_inode.t → iProp Σ).

  Definition Pinode γblocks γused (s: inode.t): iProp Σ :=
    "Hownblocks" ∷ own γblocks (◯ Excl' (s.(inode.blocks): listLO Block)) ∗
    "Hused1" ∷ own γused (●{1/2} Excl' s.(inode.addrs)).

  Definition Palloc γused (s: alloc.t): iProp Σ :=
    "Hused2" ∷ own γused (●{1/2} Excl' (alloc.used s)).

  Definition s_inode_inv γblocks γused (blocks: list Block) (used: gset u64): iProp Σ :=
    "Hγblocks" ∷ own γblocks (● Excl' (blocks : listLO Block)) ∗
    "Hγused" ∷ own γused (◯ Excl' used).

  Definition is_single_inode l (sz: Z) k' : iProp Σ :=
    ∃ (inode_ref alloc_ref: loc) γinode γalloc γused γblocks,
      "#i" ∷ readonly (l ↦[SingleInode.S :: "i"] #inode_ref) ∗
      "#alloc" ∷ readonly (l ↦[SingleInode.S :: "alloc"] #alloc_ref) ∗
      "#Hinode" ∷ is_inode inode_ref (LVL k') γinode (Pinode γblocks γused) (U64 0) ∗
      "#Halloc" ∷ is_allocator (Palloc γused)
        (λ a, ∃ b, int.val a d↦ b)
        allocN alloc_ref (rangeSet 1 (sz-1)) γalloc k' ∗
      "#Hinv" ∷ inv N (∃ σ (used:gset u64),
                          s_inode_inv γblocks γused σ used ∗
                          P σ)
  .

  Instance s_inode_inv_Timeless :
    Timeless (s_inode_inv γblocks γused blocks used).
  Proof. apply _. Qed.

  (* TODO: needs allocator and inode crash conditions and init obligations *)
  Theorem wpc_Open {k E2} (d_ref: loc) (sz: u64)
          k' γblocks γused σ0 :
    (* TODO: export inode_crash_cond to capture this *)
    {{{ (∃ s addrs, is_inode_durable (U64 0) s addrs ∗ Pinode γblocks γused s) ∗ P σ0 }}}
      Open #d_ref #sz @ NotStuck; k; ⊤; E2
    {{{ l, RET #l; is_single_inode l (int.val sz) k' }}}
    {{{ ∃ σ', P σ' }}}.
  Proof.
  Abort.

  Lemma alloc_used_reserve s u :
    u ∈ alloc.free s →
    alloc.used (<[u:=block_reserved]> s) =
    alloc.used s.
  Proof.
    rewrite /alloc.free /alloc.used.
    intros Hufree.
    apply elem_of_dom in Hufree as [status Hufree].
    apply map_filter_lookup_Some in Hufree as [Hufree ?];
      simpl in *; subst.
    rewrite map_filter_insert_not_strong //=.
  Admitted.

  Lemma alloc_free_reserved s a :
    s !! a = Some block_reserved →
    alloc.used (<[a := block_free]> s) =
    alloc.used s.
  Proof.
    rewrite /alloc.used.
    intros Hareserved.
    rewrite map_filter_insert_not_strong //=.
  Admitted.

  Lemma alloc_used_insert s a :
    alloc.used (<[a := block_used]> s) = {[a]} ∪ alloc.used s.
  Proof.
    rewrite /alloc.used.
    rewrite map_filter_insert //.
    set_solver.
  Qed.

  Theorem wpc_Append {k E2} (Q: iProp Σ) l sz b_s b0 k' :
    (3 + k < k')%nat →
    {{{ "Hinode" ∷ is_single_inode l sz k' ∗
        "Hb" ∷ is_block b_s 1 b0 ∗
        "Hfupd" ∷ ((∀ σ σ',
          ⌜σ' = σ ++ [b0]⌝ -∗
        (* TODO: to be able to use an invariant within another HOCAP fupd I had
        to make this fupd from [▷ P(σ)] to [▷ P(σ')] rather than our usual
        [P(σ)] to [P(σ')]; normally we seem to get around this by linearizing at
        a Skip? *)
         ▷ P σ ={⊤ ∖ ↑allocN ∖ ↑N}=∗ ▷ P σ' ∗ Q))
    }}}
      SingleInode__Append #l (slice_val b_s) @ NotStuck; LVL (S (S (S (S k)))); ⊤; E2
    {{{ (ok: bool), RET #ok; if ok then Q else emp }}}
    {{{ True }}}.
  Proof.
    iIntros (? Φ Φc) "Hpre HΦ"; iNamed "Hpre".
    wpc_call.
    { crash_case; auto. }
    iCache with "HΦ".
    { crash_case; auto. }
    iNamed "Hinode".
    wpc_bind (struct.loadF _ _ _); wpc_frame "HΦ".
    wp_loadField.
    iNamed 1.
    wpc_bind (struct.loadF _ _ _); wpc_frame "HΦ".
    wp_loadField.
    iNamed 1.
    wpc_apply (wpc_Inode__Append Q emp%I
                 with "[$Hb $Hinode $Halloc Hfupd]");
      try lia; try solve_ndisj.
    {
      iSplitR.
      { by iIntros "_". }
      iSplit; [ | iSplit; [ | iSplit ] ]; try iModIntro.
      - iIntros (s s' ma Hma) "HPalloc".
        destruct ma; intuition subst; auto.
        iEval (rewrite /Palloc) in "HPalloc"; iNamed.
        iEval (rewrite /Palloc /named).
        rewrite alloc_used_reserve //.
      - iIntros (a s s') "HPalloc".
        iEval (rewrite /Palloc) in "HPalloc"; iNamed.
        iEval (rewrite /Palloc /named).
        rewrite alloc_free_reserved //.
      - iIntros (σ σ' addr' -> Hwf s Hreserved) "(HPinode&HPalloc)".
        iEval (rewrite /Palloc) in "HPalloc"; iNamed.
        iNamed "HPinode".
        iDestruct (ghost_var_frac_frac_agree with "Hused1 Hused2") as %Heq;
          rewrite -Heq.
        iCombine "Hused1 Hused2" as "Hused".
        iInv "Hinv" as (σ0 used) "[>Hinner HP]" "Hclose".
        iNamed "Hinner".
        iDestruct (ghost_var_agree with "Hused Hγused") as %?; subst.
        iMod (ghost_var_update _ (union {[addr']} σ.(inode.addrs))
                               with "Hused Hγused") as
            "[Hused Hγused]".
        iDestruct (ghost_var_agree with "Hγblocks Hownblocks") as %?; subst.
        iMod (ghost_var_update _ ((σ.(inode.blocks) ++ [b0]) : listLO Block)
                with "Hγblocks Hownblocks") as "[Hγblocks Hownblocks]".
        iMod ("Hfupd" with "[% //] [$HP]") as "[HP HQ]".
        iDestruct "Hused" as "[Hused1 Hused2]".
        iMod ("Hclose" with "[Hγused Hγblocks HP]") as "_".
        { iNext.
          iExists _, _; iFrame. }
        iModIntro.
        iFrame.
        rewrite /Palloc.
        rewrite alloc_used_insert -Heq.
        iFrame.
      - auto.
    }
    iSplit.
    { iIntros "_".
      iFromCache. }
    iNext.
    iIntros (ok) "HQ".
    iApply "HΦ"; auto.
  Qed.

End goose.
