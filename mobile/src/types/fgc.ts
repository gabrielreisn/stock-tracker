/** Banco Central IF.data prudential group; all members share one FGC limit. */
export interface Conglomerate {
  code: string;
  name: string;
  members: string[];
}
export type Conglomerates = Record<string, Conglomerate>;
