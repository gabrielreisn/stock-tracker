/** Insert a category at its drop position, retaining IDs, mappings and limits. */
export function reorderCategory<T extends { id: string }>(categories: T[], id: string, destination: number): T[] {
  const source = categories.findIndex(category => category.id === id);
  if (source < 0 || destination < 0 || destination >= categories.length || source === destination) return categories;
  const next = [...categories];
  const [category] = next.splice(source, 1);
  next.splice(destination, 0, category);
  return next;
}
export function categoryDropIndex(frames: { y: number; height: number }[], center: number) {
  let target = 0;
  for (let index = 1; index < frames.length; index += 1) {
    if (center >= frames[index].y) target = index;
  }
  return target;
}
export interface CategoryScrollMetrics { offset: number; max: number }
